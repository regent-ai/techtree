defmodule TechTree.LocalCache do
  @moduledoc false

  @cache_name :techtree_cache

  def child_spec, do: RegentCache.child_spec(@cache_name)
  def status, do: RegentCache.status(@cache_name)

  def fetch(key, ttl_seconds, fun) do
    case RegentCache.fetch(@cache_name, key, ttl_seconds, fun) do
      {:ok, value} -> {:ok, restore_known_keys(value)}
      other -> other
    end
  end

  def delete(keys), do: RegentCache.delete(@cache_name, keys)

  def set_add(key, member, ttl_seconds),
    do: RegentCache.set_add(@cache_name, key, member, ttl_seconds)

  def set_remove(key, member, ttl_seconds),
    do: RegentCache.set_remove(@cache_name, key, member, ttl_seconds)

  def set_members(key), do: RegentCache.set_members(@cache_name, key)

  def get(key) when is_binary(key), do: Cachex.get(@cache_name, key)

  def put(key, value, ttl_ms) when is_binary(key) and is_integer(ttl_ms) and ttl_ms > 0 do
    Cachex.put(@cache_name, key, value, ttl: ttl_ms)
  end

  defp restore_known_keys(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {restore_key(key), restore_known_keys(item)} end)
  end

  defp restore_known_keys(value) when is_list(value), do: Enum.map(value, &restore_known_keys/1)
  defp restore_known_keys(value), do: value

  defp restore_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp restore_key(key), do: key
end
