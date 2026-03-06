defmodule TechTreeWeb.ControllerHelpers do
  @moduledoc false

  alias TechTree.Agents

  @spec ensure_current_agent(Plug.Conn.t()) :: TechTree.Agents.AgentIdentity.t()
  def ensure_current_agent(conn) do
    Agents.upsert_verified_agent!(conn.assigns.current_agent_claims)
  end

  @spec fetch_param(map(), String.t(), atom()) :: term()
  def fetch_param(params, string_key, atom_key) do
    Map.get(params, string_key, Map.get(params, atom_key))
  end

  @spec parse_positive_int_param(map(), String.t(), atom()) ::
          {:ok, integer()} | {:error, :required | :invalid}
  def parse_positive_int_param(params, string_key, atom_key) do
    params
    |> fetch_param(string_key, atom_key)
    |> parse_positive_int()
  end

  @spec parse_positive_int(term()) :: {:ok, integer()} | {:error, :required | :invalid}
  def parse_positive_int(nil), do: {:error, :required}
  def parse_positive_int(value) when is_integer(value) and value > 0, do: {:ok, value}

  def parse_positive_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> {:error, :invalid}
    end
  end

  def parse_positive_int(_value), do: {:error, :invalid}

  @spec normalize_optional_text(term()) :: String.t() | nil
  def normalize_optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def normalize_optional_text(_value), do: nil
end