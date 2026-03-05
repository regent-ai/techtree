defmodule TechTree.Types.Ltree do
  @moduledoc false
  @behaviour Ecto.Type

  @impl true
  @spec type() :: :string
  def type, do: :string

  @impl true
  @spec cast(term()) :: {:ok, String.t() | nil} | :error
  def cast(nil), do: {:ok, nil}

  def cast(value) when is_binary(value) do
    if valid_ltree?(value), do: {:ok, value}, else: :error
  end

  def cast(_value), do: :error

  @impl true
  @spec dump(term()) :: {:ok, String.t() | nil} | :error
  def dump(nil), do: {:ok, nil}
  def dump(value) when is_binary(value), do: {:ok, value}
  def dump(_value), do: :error

  @impl true
  @spec load(term()) :: {:ok, String.t() | nil} | :error
  def load(nil), do: {:ok, nil}
  def load(value) when is_binary(value), do: {:ok, value}
  def load(_value), do: :error

  @impl true
  @spec embed_as(term()) :: :self
  def embed_as(_format), do: :self

  @impl true
  @spec equal?(term(), term()) :: boolean()
  def equal?(left, right), do: left == right

  @spec valid_ltree?(String.t()) :: boolean()
  defp valid_ltree?(value) do
    Regex.match?(~r/^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*$/, value)
  end
end
