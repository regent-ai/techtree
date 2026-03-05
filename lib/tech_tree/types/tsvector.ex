defmodule TechTree.Types.Tsvector do
  @moduledoc false
  @behaviour Ecto.Type

  @impl true
  @spec type() :: :string
  def type, do: :string

  @impl true
  @spec cast(term()) :: {:ok, String.t() | nil} | :error
  def cast(nil), do: {:ok, nil}
  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(value) when is_list(value), do: {:ok, lexemes_to_text(value)}
  def cast(_value), do: :error

  @impl true
  @spec dump(term()) :: {:ok, String.t() | nil} | :error
  def dump(nil), do: {:ok, nil}
  def dump(value) when is_binary(value), do: {:ok, value}
  def dump(value) when is_list(value), do: {:ok, lexemes_to_text(value)}
  def dump(_value), do: :error

  @impl true
  @spec load(term()) :: {:ok, String.t() | nil} | :error
  def load(nil), do: {:ok, nil}
  def load(value) when is_binary(value), do: {:ok, value}
  def load(value) when is_list(value), do: {:ok, lexemes_to_text(value)}
  def load(_value), do: :error

  @impl true
  @spec embed_as(term()) :: :self
  def embed_as(_format), do: :self

  @impl true
  @spec equal?(term(), term()) :: boolean()
  def equal?(left, right), do: left == right

  @spec lexemes_to_text([term()]) :: String.t()
  defp lexemes_to_text(values) do
    values
    |> Enum.map(&lexeme_word/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  @spec lexeme_word(term()) :: String.t()
  defp lexeme_word(%{word: word}) when is_binary(word), do: word
  defp lexeme_word(%{"word" => word}) when is_binary(word), do: word
  defp lexeme_word(word) when is_binary(word), do: word
  defp lexeme_word(_other), do: ""
end
