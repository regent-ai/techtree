defmodule TechTreeWeb.OrcidAuthController do
  use TechTreeWeb, :controller

  alias Phoenix.Token
  alias TechTree.BBH

  def start(conn, %{"request_id" => request_id}) do
    token = Token.sign(TechTreeWeb.Endpoint, "bbh_orcid_link", request_id)
    redirect(conn, to: ~p"/auth/orcid/callback?token=#{token}")
  end

  def callback(conn, %{"token" => token}) do
    case Token.verify(TechTreeWeb.Endpoint, "bbh_orcid_link", token, max_age: 900) do
      {:ok, request_id} ->
        case BBH.complete_orcid_link(request_id) do
          {:ok, reviewer} ->
            html(
              conn,
              """
              <html><body><main><h1>ORCID linked</h1><p>#{reviewer.wallet_address} is now linked. You can return to Regents CLI.</p></main></body></html>
              """
            )

          {:error, _reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> html(
              "<html><body><main><h1>ORCID link failed</h1><p>The link request could not be completed.</p></main></body></html>"
            )
        end

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> html(
          "<html><body><main><h1>ORCID link failed</h1><p>The link token is invalid or expired.</p></main></body></html>"
        )
    end
  end
end
