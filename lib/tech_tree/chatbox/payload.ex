defmodule TechTree.Chatbox.Payload do
  @moduledoc false

  alias TechTree.Agents.AgentIdentity

  @spec parse_limit(map(), pos_integer(), pos_integer()) :: pos_integer()
  def parse_limit(params, default_limit, max_limit) when is_map(params) do
    params
    |> Map.get("limit", default_limit)
    |> case do
      value when is_integer(value) and value > 0 ->
        min(value, max_limit)

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {parsed, ""} when parsed > 0 -> min(parsed, max_limit)
          _ -> default_limit
        end

      _ ->
        default_limit
    end
  end

  @spec parse_before_id(map()) :: integer() | nil
  def parse_before_id(params) when is_map(params) do
    params
    |> Map.get("before")
    |> case do
      nil ->
        nil

      value when is_integer(value) and value > 0 ->
        value

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {parsed, ""} when parsed > 0 -> parsed
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @spec parse_message_id(term(), atom()) :: {:ok, integer()} | {:error, atom()}
  def parse_message_id(value, error_code) do
    case value do
      id when is_integer(id) and id > 0 ->
        {:ok, id}

      id when is_binary(id) ->
        case Integer.parse(String.trim(id)) do
          {parsed, ""} when parsed > 0 -> {:ok, parsed}
          _ -> {:error, error_code}
        end

      _ ->
        {:error, error_code}
    end
  end

  @spec normalize_message_body(map(), pos_integer()) ::
          {:ok, String.t()} | {:error, :body_required | :body_too_long}
  def normalize_message_body(attrs, max_length) when is_map(attrs) do
    body =
      attrs
      |> Map.get("body")
      |> case do
        nil -> nil
        value -> value
      end

    cond do
      not is_binary(body) ->
        {:error, :body_required}

      true ->
        trimmed = String.trim(body)

        cond do
          trimmed == "" -> {:error, :body_required}
          String.length(trimmed) > max_length -> {:error, :body_too_long}
          true -> {:ok, trimmed}
        end
    end
  end

  @spec normalize_client_message_id(map()) ::
          {:ok, String.t() | nil} | {:error, :invalid_client_message_id}
  def normalize_client_message_id(attrs) when is_map(attrs) do
    attrs
    |> Map.get("client_message_id")
    |> case do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:ok, nil}
          normalized when byte_size(normalized) > 128 -> {:error, :invalid_client_message_id}
          normalized -> {:ok, normalized}
        end

      _ ->
        {:error, :invalid_client_message_id}
    end
  end

  @spec normalize_reaction_emoji(map()) :: {:ok, String.t()} | {:error, :invalid_reaction_emoji}
  def normalize_reaction_emoji(attrs) when is_map(attrs) do
    attrs
    |> Map.get(
      "emoji",
      Map.get(attrs, "emoji")
    )
    |> case do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, :invalid_reaction_emoji}
          normalized when byte_size(normalized) > 32 -> {:error, :invalid_reaction_emoji}
          normalized -> {:ok, normalized}
        end

      _ ->
        {:error, :invalid_reaction_emoji}
    end
  end

  @spec normalize_reaction_operation(map()) ::
          {:ok, :add | :remove} | {:error, :invalid_reaction_operation}
  def normalize_reaction_operation(attrs) when is_map(attrs) do
    attrs
    |> Map.get(
      "op",
      Map.get(attrs, "op", "add")
    )
    |> case do
      value when is_binary(value) ->
        case String.trim(value) |> String.downcase() do
          "add" -> {:ok, :add}
          "remove" -> {:ok, :remove}
          _ -> {:error, :invalid_reaction_operation}
        end

      _ ->
        {:error, :invalid_reaction_operation}
    end
  end

  @spec normalize_room_param(map(), String.t()) :: String.t()
  def normalize_room_param(params, default) when is_map(params) do
    params
    |> Map.get("room_id", default)
    |> case do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> default
          trimmed -> trimmed
        end

      _ ->
        default
    end
  end

  @spec normalize_agent_room(map(), AgentIdentity.t()) :: String.t()
  def normalize_agent_room(attrs, %AgentIdentity{id: id}) when is_map(attrs) do
    case Map.get(attrs, "room", "agent") do
      "agent" -> "agent:#{id}"
      _ -> "agent:#{id}"
    end
  end

  @spec validate_transport_payload(binary(), map()) ::
          :ok | {:error, :topic_mismatch | :invalid_actor_type | :invalid_payload}
  def validate_transport_payload(topic, %{
        "transport_msg_id" => transport_msg_id,
        "topic" => payload_topic,
        "actor" => %{"type" => actor_type},
        "inserted_at" => inserted_at
      })
      when is_binary(topic) and is_binary(transport_msg_id) and is_binary(payload_topic) and
             is_binary(actor_type) and is_binary(inserted_at) do
    cond do
      topic != payload_topic -> {:error, :topic_mismatch}
      actor_type not in ["human", "agent"] -> {:error, :invalid_actor_type}
      true -> :ok
    end
  end

  def validate_transport_payload(_topic, _payload), do: {:error, :invalid_payload}

  @spec parse_transport_datetime(term()) :: DateTime.t() | nil
  def parse_transport_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  def parse_transport_datetime(_value), do: nil
end
