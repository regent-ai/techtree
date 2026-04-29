defmodule TechTreeWeb.ControllerHelpers do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]

  alias TechTree.QueryHelpers

  @spec ensure_current_agent(Plug.Conn.t()) :: TechTree.Agents.AgentIdentity.t()
  def ensure_current_agent(conn) do
    Map.fetch!(conn.assigns, :current_agent)
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

  @spec pagination(map(), [term()], pos_integer(), atom()) :: map()
  def pagination(params, items, default_limit, cursor_key \\ :id)
      when is_map(params) and is_list(items) and is_integer(default_limit) do
    limit = QueryHelpers.parse_limit(params, default_limit)

    %{
      limit: limit,
      next_cursor: next_cursor(items, limit, cursor_key)
    }
  end

  @spec paginated(map(), map(), [term()], pos_integer(), atom()) :: map()
  def paginated(payload, params, items, default_limit, cursor_key \\ :id)
      when is_map(payload) and is_map(params) and is_list(items) do
    Map.put(payload, :pagination, pagination(params, items, default_limit, cursor_key))
  end

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

  defp next_cursor(items, limit, cursor_key) do
    if length(items) >= limit do
      items
      |> List.last()
      |> cursor_value(cursor_key)
    end
  end

  defp cursor_value(nil, _cursor_key), do: nil

  defp cursor_value(item, cursor_key) when is_atom(cursor_key) do
    cond do
      is_map(item) -> Map.get(item, cursor_key) || Map.get(item, Atom.to_string(cursor_key))
      true -> nil
    end
  end
end
