defmodule TechTreeWeb.ChatboxController do
  use TechTreeWeb, :controller

  alias TechTree.RateLimit
  alias TechTree.Chatbox
  alias TechTreeWeb.ApiError
  alias TechTreeWeb.ControllerHelpers
  alias TechTreeWeb.PublicEncoding

  @spec messages(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def messages(conn, params) do
    with :ok <- ensure_public_room(params) do
      %{messages: messages, next_cursor: next_cursor} = Chatbox.list_public_messages(params)

      json(conn, %{
        data: PublicEncoding.encode_chatbox_messages(messages),
        next_cursor: next_cursor
      })
    else
      {:error, :invalid_chatbox_room} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_chatbox_room"})
    end
  end

  @spec create_message(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_message(conn, params) do
    human = conn.assigns.current_human

    with :ok <- enforce_message_limit(conn, human, params),
         {:ok, message, create_status} <- Chatbox.create_human_message(human, params) do
      conn
      |> put_status(if(create_status == :created, do: :created, else: :ok))
      |> json(%{data: PublicEncoding.encode_chatbox_message(message)})
    else
      {:error, %{code: :rate_limited, retry_after_ms: retry_after_ms}} ->
        render_rate_limit(conn, "message_rate_limited", retry_after_ms)

      {:error, %{code: :duplicate_message, retry_after_ms: retry_after_ms}} ->
        render_rate_limit(conn, "duplicate_message_cooldown", retry_after_ms)

      {:error, :human_banned} ->
        ApiError.render(conn, :forbidden, %{
          code: "human_banned",
          message: "banned humans cannot post to chatbox"
        })

      {:error, :xmtp_identity_required} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "chat_identity_required",
          message: "finish secure room setup before you post in the public room"
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "message_create_failed",
          details: ApiError.translate_changeset(changeset)
        })

      {:error, :body_required} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "body_required",
          message: "message body required"
        })

      {:error, :body_too_long} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "body_too_long",
          message: "message body exceeds maximum length"
        })

      {:error, :invalid_reply_to_message} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "invalid_reply_to_message",
          message: "reply target not found"
        })

      {:error, :invalid_client_message_id} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "invalid_client_message_id",
          message: "client_message_id is invalid"
        })
    end
  end

  @spec react_message(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def react_message(conn, %{"id" => message_id} = params) do
    human = conn.assigns.current_human

    case enforce_reaction_limit(conn, human) do
      :ok ->
        react_message_with_limit(conn, human, message_id, params)

      {:error, %{retry_after_ms: retry_after_ms}} ->
        render_rate_limit(conn, "reaction_rate_limited", retry_after_ms)
    end
  end

  defp react_message_with_limit(conn, human, message_id, params) do
    case Chatbox.react_to_message(human, message_id, params) do
      {:ok, message} ->
        json(conn, %{data: PublicEncoding.encode_chatbox_message(message)})

      {:error, :human_banned} ->
        ApiError.render(conn, :forbidden, %{
          code: "human_banned",
          message: "banned humans cannot react in chatbox"
        })

      {:error, :xmtp_identity_required} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "chat_identity_required",
          message: "finish secure room setup before you react in the public room"
        })

      {:error, :message_not_found} ->
        ApiError.render(conn, :not_found, %{
          code: "message_not_found",
          message: "message not found"
        })

      {:error, :invalid_reaction_emoji} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "invalid_reaction_emoji",
          message: "reaction emoji is invalid"
        })

      {:error, :invalid_reaction_operation} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "invalid_reaction_operation",
          message: "reaction operation is invalid"
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "reaction_update_failed",
          details: ApiError.translate_changeset(changeset)
        })
    end
  end

  defp enforce_message_limit(conn, human, params) do
    RateLimit.allow_chatbox_message(
      actor_scope: "human:#{human.id}",
      principal_scope: "privy:#{human.privy_user_id}",
      ip_scope: ControllerHelpers.client_ip_scope(conn),
      message_body: params["body"],
      idempotency_key: params["client_message_id"]
    )
  end

  defp enforce_reaction_limit(conn, human) do
    RateLimit.allow_chatbox_reaction(
      actor_scope: "human:#{human.id}",
      principal_scope: "privy:#{human.privy_user_id}",
      ip_scope: ControllerHelpers.client_ip_scope(conn)
    )
  end

  defp render_rate_limit(conn, code, retry_after_ms) do
    retry_after_seconds = retry_after_ms |> Kernel./(1_000) |> Float.ceil() |> trunc()

    conn
    |> put_resp_header("retry-after", Integer.to_string(max(retry_after_seconds, 1)))
    |> ApiError.render(:too_many_requests, %{
      code: code,
      retry_after_ms: retry_after_ms
    })
  end

  defp ensure_public_room(params) do
    case Map.get(params, "room") do
      nil ->
        :ok

      value when is_binary(value) ->
        case String.trim(value) do
          "webapp" -> :ok
          _ -> {:error, :invalid_chatbox_room}
        end

      _ ->
        {:error, :invalid_chatbox_room}
    end
  end
end
