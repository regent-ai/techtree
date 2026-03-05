defmodule TechTree.RateLimit do
  @moduledoc false

  @node_create_ttl_seconds 3600
  @comment_create_ttl_seconds 300
  @trollbox_post_ttl_seconds 15
  @trollbox_burst_ttl_seconds 300
  @trollbox_burst_limit 10

  @spec check_node_create!(String.t()) :: :ok | {:error, :rate_limited}
  def check_node_create!(wallet_address) do
    if rate_limits_disabled?() do
      :ok
    else
      key = "rl:node:create:#{wallet_address}"
      set_once(key, @node_create_ttl_seconds)
    end
  end

  @spec check_comment_create!(String.t(), integer() | String.t()) :: :ok | {:error, :rate_limited}
  def check_comment_create!(wallet_address, node_id) do
    if rate_limits_disabled?() do
      :ok
    else
      key = "rl:comment:create:#{wallet_address}:#{node_id}"
      set_once(key, @comment_create_ttl_seconds)
    end
  end

  @spec check_trollbox_post!(String.t()) :: :ok | {:error, :rate_limited}
  def check_trollbox_post!(identity) do
    if rate_limits_disabled?() do
      :ok
    else
      key = "rl:trollbox:post:#{identity}"
      burst_key = "rl:trollbox:burst:#{identity}"

      with :ok <- set_once(key, @trollbox_post_ttl_seconds),
           {:ok, count} <- Redix.command(:dragonfly, ["INCR", burst_key]) do
        if count == 1 do
          _ = Redix.command(:dragonfly, ["EXPIRE", burst_key, @trollbox_burst_ttl_seconds])
        end

        if count > @trollbox_burst_limit, do: {:error, :rate_limited}, else: :ok
      else
        _ -> {:error, :rate_limited}
      end
    end
  end

  @spec set_once(String.t(), pos_integer()) :: :ok | {:error, :rate_limited}
  defp set_once(key, ttl_seconds) do
    do_set_once(key, ttl_seconds, 1)
  end

  @spec do_set_once(String.t(), pos_integer(), non_neg_integer()) :: :ok | {:error, :rate_limited}
  defp do_set_once(key, ttl_seconds, retries_left) do
    case Redix.command(:dragonfly, ["SET", key, "1", "NX", "EX", ttl_seconds]) do
      {:ok, "OK"} -> :ok
      {:ok, nil} -> {:error, :rate_limited}
      {:error, %Redix.ConnectionError{}} when retries_left > 0 -> do_set_once(key, ttl_seconds, retries_left - 1)
      _ -> {:error, :rate_limited}
    end
  end

  @spec rate_limits_disabled?() :: boolean()
  defp rate_limits_disabled? do
    Process.get(:tech_tree_disable_rate_limits, false) == true
  end
end
