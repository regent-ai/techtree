defmodule TechTree.RateLimit do
  @moduledoc false

  require Logger

  alias TechTree.QueryHelpers

  @message_policy %{capacity: 6, refill_tokens: 3, refill_interval_ms: 10_000}
  @reaction_policy %{capacity: 20, refill_tokens: 10, refill_interval_ms: 10_000}
  @node_create_policy %{capacity: 1, refill_tokens: 1, refill_interval_ms: 3_600_000}
  @comment_create_policy %{capacity: 1, refill_tokens: 1, refill_interval_ms: 300_000}
  @chatbox_post_cooldown_policy %{capacity: 1, refill_tokens: 1, refill_interval_ms: 1_000}
  @chatbox_post_burst_policy %{capacity: 10, refill_tokens: 10, refill_interval_ms: 60_000}
  @duplicate_cooldown_ms 30_000
  @cache_prefix "techtree:rate-limit:v1"

  @type limit_error_code :: :rate_limited | :duplicate_message
  @type limit_error :: %{code: limit_error_code(), retry_after_ms: pos_integer()}

  @spec policy() :: map()
  def policy do
    %{
      backend: %{
        primary: :cachex,
        scope: :single_instance
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
    cache_ready = TechTree.LocalCache.status() == :ready

    %{
      configured_backend: configured_backend,
      effective_backend: configured_backend,
      cache_ready: cache_ready,
      degraded: configured_backend == :cachex and cache_ready == false,
      last_error: if(cache_ready, do: nil, else: "local cache unavailable"),
      last_degraded_at_ms: nil,
      last_recovered_at_ms: nil
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
      rate_limit_key(["agent", "node", "create", "wallet", cache_ref(wallet_address)]),
      @node_create_policy
    )
  end

  def check_node_create!(_wallet_address), do: {:error, :rate_limited}

  @spec check_comment_create!(String.t() | nil, integer() | String.t() | nil) ::
          :ok | {:error, :rate_limited}
  def check_comment_create!(wallet_address, node_id)
      when is_binary(wallet_address) and not is_nil(node_id) do
    strict_consume_bucket(
      rate_limit_key([
        "agent",
        "comment",
        "create",
        "wallet",
        cache_ref(wallet_address),
        "node",
        QueryHelpers.normalize_id(node_id)
      ]),
      @comment_create_policy
    )
  rescue
    _ -> {:error, :rate_limited}
  end

  def check_comment_create!(_wallet_address, _node_id), do: {:error, :rate_limited}

  @spec check_chatbox_post!(String.t() | nil) :: :ok | {:error, :rate_limited}
  def check_chatbox_post!(identity) when is_binary(identity) do
    identity_ref = cache_ref(identity)

    with :ok <-
           strict_consume_bucket(
             rate_limit_key(["chatbox", "post", "cooldown", identity_ref]),
             @chatbox_post_cooldown_policy
           ) do
      strict_consume_bucket(
        rate_limit_key(["chatbox", "post", "burst", identity_ref]),
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
    case Cachex.clear(:techtree_cache) do
      {:ok, _} -> :ok
      _ -> :ok
    end
  end

  defp consume_policy_keys(namespace, policy, opts) do
    opts
    |> scopes()
    |> Enum.reduce_while(:ok, fn scope, :ok ->
      case consume_bucket(rate_limit_key([namespace, scope]), policy) do
        :ok -> {:cont, :ok}
        {:error, _limit_error} = error -> {:halt, error}
      end
    end)
  end

  defp strict_consume_bucket(key, policy) do
    case consume_bucket(key, policy) do
      :ok -> :ok
      {:error, %{code: :rate_limited}} -> {:error, :rate_limited}
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
      {prefix, value} when is_binary(value) and value != "" -> ["#{prefix}:#{cache_ref(value)}"]
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp consume_bucket(key, policy) do
    consume_bucket_in_cache(key, policy, System.system_time(:millisecond))
  end

  defp consume_bucket_in_cache(key, policy, now_ms) do
    state =
      case TechTree.LocalCache.get(key) do
        {:ok, {tokens, updated_at_ms}} -> {tokens, updated_at_ms}
        _ -> {policy.capacity * 1.0, now_ms}
      end

    {tokens, updated_at_ms} = state
    elapsed_ms = max(now_ms - updated_at_ms, 0)
    replenished = elapsed_ms * policy.refill_tokens / policy.refill_interval_ms
    available = min(policy.capacity * 1.0, tokens + replenished)

    if available < 1 do
      retry_after_ms =
        Float.ceil((1 - available) * policy.refill_interval_ms / policy.refill_tokens) |> trunc()

      _ = TechTree.LocalCache.put(key, {available, now_ms}, bucket_ttl_ms(policy))
      {:error, %{code: :rate_limited, retry_after_ms: max(retry_after_ms, 1)}}
    else
      _ = TechTree.LocalCache.put(key, {available - 1, now_ms}, bucket_ttl_ms(policy))
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
        key =
          rate_limit_key([
            "chatbox",
            "duplicate",
            "actor",
            cache_ref(actor_scope),
            "body",
            hash_body(body)
          ])

        check_duplicate_message_in_cache(key)

      _ ->
        :ok
    end
  end

  defp check_duplicate_message_in_cache(key) do
    now_ms = System.system_time(:millisecond)

    case TechTree.LocalCache.get(key) do
      {:ok, expires_at_ms} when is_integer(expires_at_ms) and expires_at_ms > now_ms ->
        {:error, %{code: :duplicate_message, retry_after_ms: expires_at_ms - now_ms}}

      _ ->
        _ = TechTree.LocalCache.put(key, now_ms + @duplicate_cooldown_ms, @duplicate_cooldown_ms)
        :ok
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

  defp configured_backend do
    case Application.get_env(:tech_tree, __MODULE__, [])[:backend] do
      :cachex -> :cachex
      _ -> :cachex
    end
  end

  defp bucket_ttl_ms(policy) do
    ceil(policy.capacity * policy.refill_interval_ms / policy.refill_tokens) * 2
  end

  defp rate_limit_key(parts) do
    Enum.join([@cache_prefix | parts], ":")
  end

  defp cache_ref(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> RegentCache.digest()
  end
end
