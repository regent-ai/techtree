defmodule TechTree.RateLimit do
  @moduledoc false

  require Logger

  alias TechTree.QueryHelpers

  @cache_app :tech_tree
  @ets_table :tech_tree_rate_limit
  @backend_status_key {:meta, :backend_status}
  @message_policy %{capacity: 6, refill_tokens: 3, refill_interval_ms: 10_000}
  @reaction_policy %{capacity: 20, refill_tokens: 10, refill_interval_ms: 10_000}
  @node_create_policy %{capacity: 1, refill_tokens: 1, refill_interval_ms: 3_600_000}
  @comment_create_policy %{capacity: 1, refill_tokens: 1, refill_interval_ms: 300_000}
  @chatbox_post_cooldown_policy %{capacity: 1, refill_tokens: 1, refill_interval_ms: 1_000}
  @chatbox_post_burst_policy %{capacity: 10, refill_tokens: 10, refill_interval_ms: 60_000}
  @duplicate_cooldown_ms 30_000

  @bucket_script """
  local key = KEYS[1]
  local now_ms = tonumber(ARGV[1])
  local capacity = tonumber(ARGV[2])
  local refill_tokens = tonumber(ARGV[3])
  local refill_interval_ms = tonumber(ARGV[4])
  local requested = tonumber(ARGV[5])

  local state = redis.call("HMGET", key, "tokens", "updated_at_ms")
  local tokens = tonumber(state[1])
  local updated_at_ms = tonumber(state[2])

  if tokens == nil or updated_at_ms == nil then
    tokens = capacity
    updated_at_ms = now_ms
  else
    local elapsed_ms = math.max(0, now_ms - updated_at_ms)
    local replenished = (elapsed_ms * refill_tokens) / refill_interval_ms
    tokens = math.min(capacity, tokens + replenished)
    updated_at_ms = now_ms
  end

  local ttl_ms = math.ceil((capacity * refill_interval_ms) / refill_tokens) * 2

  if tokens < requested then
    local missing = requested - tokens
    local retry_after_ms = math.ceil((missing * refill_interval_ms) / refill_tokens)
    redis.call("HMSET", key, "tokens", tokens, "updated_at_ms", updated_at_ms)
    redis.call("PEXPIRE", key, ttl_ms)
    return {0, math.max(retry_after_ms, 1)}
  end

  tokens = tokens - requested
  redis.call("HMSET", key, "tokens", tokens, "updated_at_ms", updated_at_ms)
  redis.call("PEXPIRE", key, ttl_ms)
  return {1, 0}
  """

  @type limit_error_code :: :rate_limited | :duplicate_message
  @type limit_error :: %{code: limit_error_code(), retry_after_ms: pos_integer()}

  @spec policy() :: map()
  def policy do
    %{
      backend: %{
        primary: :dragonfly,
        failure_mode: :fail_closed
      },
      agent_node_create: @node_create_policy,
      agent_comment_create: @comment_create_policy,
      chatbox_message: Map.put(@message_policy, :duplicate_cooldown_ms, @duplicate_cooldown_ms),
      chatbox_reaction: @reaction_policy
    }
  end

  @spec status() :: map()
  def status do
    configured_backend = configured_backend()
    dragonfly_enabled = RegentCache.Dragonfly.enabled?(@cache_app)
    {dragonfly_reachable, live_error} = dragonfly_health(configured_backend, dragonfly_enabled)
    meta = reconcile_backend_status(configured_backend, live_error)

    %{
      configured_backend: configured_backend,
      effective_backend: configured_backend,
      dragonfly_enabled: dragonfly_enabled,
      dragonfly_reachable: dragonfly_reachable,
      degraded: configured_backend == :dragonfly and dragonfly_reachable == false,
      last_error: live_error || meta.last_error,
      last_degraded_at_ms: meta.last_degraded_at_ms,
      last_recovered_at_ms: meta.last_recovered_at_ms
    }
  end

  @spec allow_chatbox_message(keyword()) :: :ok | {:error, limit_error()}
  def allow_chatbox_message(opts) do
    result =
      with :ok <- consume_policy_keys("chatbox:message", @message_policy, opts) do
        check_duplicate_message(opts)
      end

    emit_throttle_event(result, :message)
    result
  end

  @spec allow_chatbox_reaction(keyword()) :: :ok | {:error, limit_error()}
  def allow_chatbox_reaction(opts) do
    result = consume_policy_keys("chatbox:reaction", @reaction_policy, opts)
    emit_throttle_event(result, :reaction)
    result
  end

  @spec allow_agent_node_create(keyword()) :: :ok | {:error, limit_error()}
  def allow_agent_node_create(opts) do
    result = consume_policy_keys("agent:node:create", @node_create_policy, opts)
    emit_throttle_event(result, :node_create)
    result
  end

  @spec allow_agent_comment_create(keyword()) :: :ok | {:error, limit_error()}
  def allow_agent_comment_create(opts) do
    result = consume_policy_keys("agent:comment:create", @comment_create_policy, opts)
    emit_throttle_event(result, :comment_create)
    result
  end

  @spec check_node_create!(String.t() | nil) :: :ok | {:error, :rate_limited}
  def check_node_create!(wallet_address) when is_binary(wallet_address) do
    strict_consume_bucket(
      "watch:node:create:#{String.trim(wallet_address)}",
      @node_create_policy
    )
  end

  def check_node_create!(_wallet_address), do: {:error, :rate_limited}

  @spec check_comment_create!(String.t() | nil, integer() | String.t() | nil) ::
          :ok | {:error, :rate_limited}
  def check_comment_create!(wallet_address, node_id)
      when is_binary(wallet_address) and not is_nil(node_id) do
    strict_consume_bucket(
      "watch:comment:create:#{String.trim(wallet_address)}:#{QueryHelpers.normalize_id(node_id)}",
      @comment_create_policy
    )
  rescue
    _ -> {:error, :rate_limited}
  end

  def check_comment_create!(_wallet_address, _node_id), do: {:error, :rate_limited}

  @spec check_chatbox_post!(String.t() | nil) :: :ok | {:error, :rate_limited}
  def check_chatbox_post!(identity) when is_binary(identity) do
    normalized_identity = String.trim(identity)

    with :ok <-
           strict_consume_bucket(
             "rl:chatbox:post:#{normalized_identity}",
             @chatbox_post_cooldown_policy
           ) do
      strict_consume_bucket(
        "rl:chatbox:burst:#{normalized_identity}",
        @chatbox_post_burst_policy
      )
    end
  end

  def check_chatbox_post!(_identity), do: {:error, :rate_limited}

  defp emit_throttle_event(:ok, _subject), do: :ok

  defp emit_throttle_event({:error, %{code: code, retry_after_ms: retry_after_ms}}, :message) do
    emit_throttle_telemetry(
      [:tech_tree, :chatbox, :write, :throttle],
      :message,
      code,
      retry_after_ms
    )
  end

  defp emit_throttle_event({:error, %{code: code, retry_after_ms: retry_after_ms}}, :reaction) do
    emit_throttle_telemetry(
      [:tech_tree, :chatbox, :write, :throttle],
      :reaction,
      code,
      retry_after_ms
    )
  end

  defp emit_throttle_event({:error, %{code: code, retry_after_ms: retry_after_ms}}, subject) do
    emit_throttle_telemetry(
      [:tech_tree, :agent, :write, :throttle],
      subject,
      code,
      retry_after_ms
    )
  end

  defp emit_throttle_telemetry(event_name, subject, code, retry_after_ms) do
    :telemetry.execute(
      event_name,
      %{count: 1, retry_after_ms: retry_after_ms},
      %{subject: Atom.to_string(subject), code: Atom.to_string(code)}
    )
  end

  @spec reset!() :: :ok
  def reset! do
    case :ets.whereis(@ets_table) do
      :undefined -> :ok
      tid -> :ets.delete_all_objects(tid) && :ok
    end
  end

  defp consume_policy_keys(namespace, policy, opts) do
    opts
    |> scopes()
    |> Enum.reduce_while(:ok, fn scope, :ok ->
      case consume_bucket("#{namespace}:#{scope}", policy) do
        :ok -> {:cont, :ok}
        {:error, _limit_error} = error -> {:halt, error}
      end
    end)
  end

  defp strict_consume_bucket(key, policy) do
    args = [
      @bucket_script,
      "1",
      key,
      Integer.to_string(System.system_time(:millisecond)),
      Integer.to_string(policy.capacity),
      Integer.to_string(policy.refill_tokens),
      Integer.to_string(policy.refill_interval_ms),
      "1"
    ]

    case RegentCache.Dragonfly.command(@cache_app, ["EVAL" | args]) do
      {:ok, [1, 0]} -> :ok
      {:ok, [0, _retry_after_ms]} -> {:error, :rate_limited}
      {:error, _reason} -> {:error, :rate_limited}
      _ -> {:error, :rate_limited}
    end
  rescue
    _ -> {:error, :rate_limited}
  end

  defp scopes(opts) do
    [
      {:actor, Keyword.get(opts, :actor_scope)},
      {:principal, Keyword.get(opts, :principal_scope)},
      {:ip, Keyword.get(opts, :ip_scope)}
    ]
    |> Enum.flat_map(fn
      {prefix, value} when is_binary(value) and value != "" -> ["#{prefix}:#{value}"]
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp consume_bucket(key, policy) do
    now_ms = System.system_time(:millisecond)

    args = [
      @bucket_script,
      "1",
      key,
      Integer.to_string(now_ms),
      Integer.to_string(policy.capacity),
      Integer.to_string(policy.refill_tokens),
      Integer.to_string(policy.refill_interval_ms),
      "1"
    ]

    case rate_limit_backend() do
      :dragonfly ->
        case RegentCache.Dragonfly.command(@cache_app, ["EVAL" | args]) do
          {:ok, [1, 0]} ->
            record_backend_healthy(:consume_bucket)
            :ok

          {:ok, [0, retry_after_ms]} when is_integer(retry_after_ms) ->
            record_backend_healthy(:consume_bucket)
            {:error, %{code: :rate_limited, retry_after_ms: max(retry_after_ms, 1)}}

          {:ok, unexpected_reply} ->
            fail_closed_limit(:consume_bucket, {:unexpected_reply, unexpected_reply})

          {:error, reason} ->
            fail_closed_limit(:consume_bucket, reason)

          other ->
            fail_closed_limit(:consume_bucket, {:unexpected_result, other})
        end

      :local ->
        consume_bucket_locally(key, policy, now_ms)
    end
  end

  defp consume_bucket_locally(key, policy, now_ms) do
    table = ensure_ets_table!()

    state =
      case :ets.lookup(table, key) do
        [{^key, tokens, updated_at_ms}] -> {tokens, updated_at_ms}
        _ -> {policy.capacity * 1.0, now_ms}
      end

    {tokens, updated_at_ms} = state
    elapsed_ms = max(now_ms - updated_at_ms, 0)
    replenished = elapsed_ms * policy.refill_tokens / policy.refill_interval_ms
    available = min(policy.capacity * 1.0, tokens + replenished)

    if available < 1 do
      retry_after_ms =
        Float.ceil((1 - available) * policy.refill_interval_ms / policy.refill_tokens) |> trunc()

      :ets.insert(table, {key, available, now_ms})
      {:error, %{code: :rate_limited, retry_after_ms: max(retry_after_ms, 1)}}
    else
      :ets.insert(table, {key, available - 1, now_ms})
      :ok
    end
  end

  defp check_duplicate_message(opts) do
    case {
      Keyword.get(opts, :idempotency_key),
      Keyword.get(opts, :actor_scope),
      normalized_message_body(Keyword.get(opts, :message_body))
    } do
      {value, _actor_scope, _body} when is_binary(value) and value != "" ->
        :ok

      {_, actor_scope, body} when is_binary(actor_scope) and is_binary(body) ->
        key = "chatbox:duplicate:#{actor_scope}:#{hash_body(body)}"

        case rate_limit_backend() do
          :dragonfly ->
            case RegentCache.Dragonfly.command(@cache_app, [
                   "SET",
                   key,
                   "1",
                   "PX",
                   Integer.to_string(@duplicate_cooldown_ms),
                   "NX"
                 ]) do
              {:ok, "OK"} ->
                record_backend_healthy(:duplicate_guard)
                :ok

              {:ok, nil} ->
                record_backend_healthy(:duplicate_guard)

                {:error,
                 %{code: :duplicate_message, retry_after_ms: duplicate_retry_after_ms(key)}}

              {:ok, unexpected_reply} ->
                fail_closed_limit(:duplicate_guard, {:unexpected_reply, unexpected_reply})

              {:error, reason} ->
                fail_closed_limit(:duplicate_guard, reason)

              other ->
                fail_closed_limit(:duplicate_guard, {:unexpected_result, other})
            end

          :local ->
            check_duplicate_message_locally(key)
        end

      _ ->
        :ok
    end
  end

  defp check_duplicate_message_locally(key) do
    table = ensure_ets_table!()
    now_ms = System.system_time(:millisecond)

    case :ets.lookup(table, key) do
      [{^key, expires_at_ms}] when expires_at_ms > now_ms ->
        {:error, %{code: :duplicate_message, retry_after_ms: expires_at_ms - now_ms}}

      _ ->
        :ets.insert(table, {key, now_ms + @duplicate_cooldown_ms})
        :ok
    end
  end

  defp duplicate_retry_after_ms(key) do
    case RegentCache.Dragonfly.command(@cache_app, ["PTTL", key]) do
      {:ok, ttl_ms} when is_integer(ttl_ms) and ttl_ms > 0 ->
        record_backend_healthy(:duplicate_retry_after)
        ttl_ms

      {:ok, _ttl_ms} ->
        record_backend_healthy(:duplicate_retry_after)
        @duplicate_cooldown_ms

      {:error, reason} ->
        record_backend_degraded(:duplicate_retry_after, reason)
        @duplicate_cooldown_ms

      other ->
        record_backend_degraded(:duplicate_retry_after, {:unexpected_result, other})
        @duplicate_cooldown_ms
    end
  end

  defp hash_body(body) do
    :sha256
    |> :crypto.hash(body)
    |> Base.encode16(case: :lower)
  end

  defp normalized_message_body(body) when is_binary(body) do
    case String.trim(body) do
      "" ->
        nil

      value ->
        value
        |> String.downcase()
        |> String.replace(~r/\s+/, " ")
    end
  end

  defp normalized_message_body(_value), do: nil

  defp rate_limit_backend, do: configured_backend()

  defp configured_backend do
    case Application.get_env(:tech_tree, __MODULE__, [])[:backend] do
      :local -> :local
      :dragonfly -> :dragonfly
      _ -> if(RegentCache.Dragonfly.enabled?(@cache_app), do: :dragonfly, else: :local)
    end
  end

  defp dragonfly_health(:local, _dragonfly_enabled), do: {nil, nil}

  defp dragonfly_health(:dragonfly, false), do: {false, "dragonfly disabled"}

  defp dragonfly_health(:dragonfly, true) do
    case RegentCache.Dragonfly.command(@cache_app, ["PING"]) do
      {:ok, "PONG"} -> {true, nil}
      {:error, reason} -> {false, inspect(reason)}
      other -> {false, inspect(other)}
    end
  end

  defp fail_closed_limit(operation, reason, retry_after_ms \\ 1_000) do
    record_backend_degraded(operation, reason)
    {:error, %{code: :rate_limited, retry_after_ms: retry_after_ms}}
  end

  defp record_backend_healthy(operation) do
    transition_backend_status(:healthy, operation, nil)
  end

  defp record_backend_degraded(operation, reason) do
    transition_backend_status(:degraded, operation, reason)
  end

  defp transition_backend_status(state, operation, reason) do
    table = ensure_ets_table!()
    now_ms = System.system_time(:millisecond)
    current = backend_status_meta(table)
    error_message = format_backend_reason(reason)

    updated =
      case state do
        :healthy ->
          maybe_emit_backend_recovered(current, operation, error_message)
          mark_backend_healthy(current, operation, now_ms)

        :degraded ->
          maybe_emit_backend_degraded(current, operation, error_message)

          %{
            current
            | degraded?: true,
              last_degraded_at_ms: now_ms,
              last_operation: operation,
              last_error: error_message
          }
      end

    :ets.insert(table, {@backend_status_key, updated})
    :ok
  end

  defp mark_backend_healthy(%{degraded?: true} = current, operation, now_ms) do
    %{
      current
      | degraded?: false,
        last_recovered_at_ms: now_ms,
        last_operation: operation,
        last_error: nil
    }
  end

  defp mark_backend_healthy(current, operation, _now_ms) do
    %{current | degraded?: false, last_operation: operation}
  end

  defp maybe_emit_backend_degraded(%{degraded?: true}, _operation, _error_message), do: :ok

  defp maybe_emit_backend_degraded(_current, operation, error_message) do
    Logger.warning(
      "dragonfly rate-limit backend degraded; failing closed operation=#{operation} reason=#{error_message}"
    )

    :telemetry.execute(
      [:tech_tree, :rate_limit, :backend, :degraded],
      %{count: 1},
      %{operation: Atom.to_string(operation), failure_mode: "fail_closed", reason: error_message}
    )

    :ok
  end

  defp maybe_emit_backend_recovered(%{degraded?: false}, _operation, _error_message), do: :ok

  defp maybe_emit_backend_recovered(_current, operation, _error_message) do
    Logger.info("dragonfly rate-limit backend recovered operation=#{operation}")

    :telemetry.execute(
      [:tech_tree, :rate_limit, :backend, :recovered],
      %{count: 1},
      %{operation: Atom.to_string(operation), backend: "dragonfly"}
    )

    :ok
  end

  defp reconcile_backend_status(:dragonfly, nil) do
    _ = record_backend_healthy(:health_check)
    backend_status_meta()
  end

  defp reconcile_backend_status(:dragonfly, live_error) do
    _ = record_backend_degraded(:health_check, live_error)
    backend_status_meta()
  end

  defp reconcile_backend_status(:local, nil), do: backend_status_meta()

  defp reconcile_backend_status(:local, live_error) do
    _ = record_backend_degraded(:health_check, live_error)
    backend_status_meta()
  end

  defp backend_status_meta do
    ensure_ets_table!()
    |> backend_status_meta()
  end

  defp backend_status_meta(table) do
    case :ets.lookup(table, @backend_status_key) do
      [{@backend_status_key, meta}] when is_map(meta) ->
        Map.merge(default_backend_status_meta(), meta)

      _ ->
        default_backend_status_meta()
    end
  end

  defp default_backend_status_meta do
    %{
      degraded?: false,
      last_error: nil,
      last_operation: nil,
      last_degraded_at_ms: nil,
      last_recovered_at_ms: nil
    }
  end

  defp format_backend_reason(nil), do: nil
  defp format_backend_reason(reason) when is_binary(reason), do: reason
  defp format_backend_reason(reason), do: inspect(reason)

  defp ensure_ets_table! do
    case :ets.whereis(@ets_table) do
      :undefined ->
        try do
          :ets.new(
            @ets_table,
            [
              :named_table,
              :public,
              :set,
              read_concurrency: true,
              write_concurrency: true
            ] ++ heir_opts()
          )
        rescue
          ArgumentError ->
            case :ets.whereis(@ets_table) do
              :undefined -> reraise ArgumentError, __STACKTRACE__
              tid -> tid
            end
        end

      tid ->
        tid
    end
  end

  defp heir_opts do
    case ets_heir_pid() do
      pid when is_pid(pid) -> [heir: pid]
      _ -> []
    end
  end

  defp ets_heir_pid do
    case Process.whereis(TechTree.Repo) do
      pid when is_pid(pid) -> pid
      _ -> nil
    end
  end
end
