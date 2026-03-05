defmodule TechTreeWeb.TrollboxController do
  use TechTreeWeb, :controller

  alias TechTree.RateLimit
  alias TechTree.XMTPMirror
  alias TechTreeWeb.ApiError
  alias TechTreeWeb.PublicEncoding

  @spec messages(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def messages(conn, params) do
    messages = XMTPMirror.list_public_messages(params)
    json(conn, %{data: PublicEncoding.encode_messages(messages)})
  end

  @spec request_join(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def request_join(conn, params) do
    human = conn.assigns.current_human

    case XMTPMirror.request_join(human, params) do
      {:ok, request} ->
        json(conn, %{data: request})

      {:error, :xmtp_inbox_already_bound} ->
        ApiError.render(conn, :conflict, %{
          code: "xmtp_inbox_already_bound",
          message: "xmtp_inbox_id already bound to this user"
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "join_request_invalid",
          details: ApiError.translate_changeset(changeset)
        })
    end
  end

  @spec membership(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def membership(conn, _params) do
    human = conn.assigns.current_human
    status = XMTPMirror.membership_for(human)
    json(conn, %{data: status})
  end

  @spec create_message(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_message(conn, params) do
    human = conn.assigns.current_human
    identity_key = "human:#{human.id}"

    with :ok <- RateLimit.check_trollbox_post!(identity_key),
         {:ok, message} <- XMTPMirror.create_human_message(human, params) do
      conn
      |> put_status(:accepted)
      |> json(%{data: PublicEncoding.encode_message(message)})
    else
      {:error, :rate_limited} ->
        ApiError.render(conn, :too_many_requests, %{
          code: "rate_limited",
          message: "trollbox post rate limit reached"
        })

      {:error, :membership_required} ->
        ApiError.render(conn, :forbidden, %{
          code: "membership_required",
          message: "join trollbox before posting"
        })

      {:error, :room_unavailable} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "room_unavailable",
          message: "trollbox room unavailable"
        })

      {:error, :missing_inbox_id} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "missing_inbox_id",
          message: "xmtp_inbox_id required"
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

      {:error, :xmtp_inbox_already_bound} ->
        ApiError.render(conn, :conflict, %{
          code: "xmtp_inbox_already_bound",
          message: "xmtp_inbox_id already bound to this user"
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "message_create_failed",
          details: ApiError.translate_changeset(changeset)
        })
    end
  end
end
