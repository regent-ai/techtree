defmodule TechTreeWeb.Human.NodeLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.HumanUX
  alias TechTree.PublicSite
  alias TechTreeWeb.{Human.NodeComponents, Human.NodePresenter, PublicSiteComponents}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket = socket |> assign(:view, :branch) |> assign(:ios_app_url, PublicSite.ios_app_url())

    {:ok,
     case HumanUX.node_page(id) do
       {:ok, page} -> NodePresenter.assign_page(socket, page)
       :error -> NodePresenter.assign_not_found(socket)
     end}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :view, HumanUX.seed_view(params["view"]))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div
      id="tree-node-page"
      class="tt-public-shell"
      phx-hook="PublicSiteMotion"
      data-motion-scope="node"
      data-motion-view={Atom.to_string(@view)}
    >
      <PublicSiteComponents.public_topbar current={:tree} ios_app_url={@ios_app_url} />

      <main class="tt-public-main">
        <%= if @not_found? do %>
          <NodeComponents.not_found />
        <% else %>
          <NodeComponents.node_page page={@page} view={@view} />
        <% end %>
      </main>
    </div>
    """
  end
end
