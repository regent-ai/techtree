defmodule TechTreeWeb.RuntimeTransportController do
  @moduledoc false
  use TechTreeWeb, :controller

  alias TechTree.P2P.Transport

  def show(conn, _params) do
    status = Transport.status()

    json(conn, %{
      data: %{
        mode: Atom.to_string(status.mode),
        ready: status.ready?,
        peer_count: status.peer_count,
        subscriptions: status.subscriptions,
        last_error: status.last_error,
        local_peer_id: status.local_peer_id,
        origin_node_id: status.origin_node_id
      }
    })
  end
end
