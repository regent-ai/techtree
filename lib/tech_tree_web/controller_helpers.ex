defmodule TechTreeWeb.ControllerHelpers do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]

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

  @spec client_ip_scope(Plug.Conn.t()) :: String.t() | nil
  def client_ip_scope(conn) do
    forwarded_for =
      conn
      |> get_req_header("x-forwarded-for")
      |> List.first()
      |> case do
        value when is_binary(value) ->
          value
          |> String.split(",", parts: 2)
          |> List.first()
          |> normalize_optional_text()

        _ ->
          nil
      end

    cond do
      is_binary(forwarded_for) ->
        forwarded_for

      is_tuple(conn.remote_ip) ->
        conn.remote_ip |> :inet.ntoa() |> to_string()

      true ->
        nil
    end
  end
end
