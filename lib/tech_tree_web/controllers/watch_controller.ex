defmodule TechTreeWeb.WatchController do
  use TechTreeWeb, :controller

  alias TechTreeWeb.ApiError
  alias TechTreeWeb.PublicEncoding
  alias TechTree.Watches

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"id" => node_id}) do
    human = conn.assigns.current_human

    case Watches.watch_human(node_id, human.id) do
      {:ok, watch} ->
        json(conn, %{data: PublicEncoding.encode_watch(watch)})

      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "watch_create_failed",
          details: ApiError.translate_changeset(changeset)
        })
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => node_id}) do
    human = conn.assigns.current_human
    :ok = Watches.unwatch_human(node_id, human.id)
    json(conn, %{ok: true})
  end

end
