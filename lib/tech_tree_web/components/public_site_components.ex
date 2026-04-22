defmodule TechTreeWeb.PublicSiteComponents do
  @moduledoc false
  use TechTreeWeb, :html

  attr :current, :atom, required: true
  attr :ios_app_url, :string, required: true

  def public_topbar(assigns) do
    assigns =
      assign(assigns, :nav_items, [
        %{key: :home, label: "Home", href: "/"},
        %{key: :tree, label: "Explore Tree", href: "/tree"},
        %{key: :activity, label: "Live Activity", href: "/activity"},
        %{key: :notebooks, label: "Notebook Gallery", href: "/notebooks"},
        %{key: :learn, label: "Research Systems", href: "/learn"},
        %{key: :bbh, label: "BBH", href: "/bbh"},
        %{key: :start, label: "Use Your Agent", href: "/start"}
      ])

    ~H"""
    <header class="tt-public-topbar" data-public-reveal>
      <a href={~p"/"} class="tt-public-brand" aria-label="Techtree home">
        <span class="tt-public-brand-mark">TT</span>
        <span class="tt-public-brand-copy">
          <span class="tt-public-brand-kicker">Techtree</span>
          <strong>Public research tree</strong>
        </span>
      </a>

      <nav class="tt-public-nav" aria-label="Public site">
        <.link
          :for={item <- @nav_items}
          navigate={item.href}
          class={["tt-public-nav-link", @current == item.key && "is-active"]}
        >
          {item.label}
        </.link>
      </nav>

      <div class="tt-public-topbar-actions">
        <.link navigate={~p"/app"} class="tt-public-app-link">Open Web App</.link>
        <a href={@ios_app_url} target="_blank" rel="noreferrer" class="tt-public-ios-link">
          Download iOS App
        </a>
      </div>
    </header>
    """
  end

  attr :kicker, :string, default: nil
  attr :title, :string, required: true
  attr :copy, :string, default: nil

  def section_heading(assigns) do
    ~H"""
    <div class="tt-public-section-head">
      <p :if={@kicker} class="tt-public-kicker">{@kicker}</p>
      <h2>{@title}</h2>
      <p :if={@copy} class="tt-public-section-copy">{@copy}</p>
    </div>
    """
  end

  attr :card, :map, required: true
  attr :dom_prefix, :string, default: "node-card"

  def node_card(assigns) do
    ~H"""
    <article id={"#{@dom_prefix}-#{@card.id}"} class="tt-public-node-card" data-public-reveal>
      <div class="tt-public-node-card-head">
        <span class="tt-public-seed-chip">{@card.seed}</span>
        <span class="tt-public-node-meta">{kind_label(@card.kind)}</span>
      </div>

      <h3>{@card.title}</h3>
      <p>{@card.summary}</p>

      <dl class="tt-public-node-stats">
        <div>
          <dt>Age</dt>
          <dd>{@card.age}</dd>
        </div>
        <div>
          <dt>Watchers</dt>
          <dd>{@card.watchers}</dd>
        </div>
        <div>
          <dt>Comments</dt>
          <dd>{@card.comments}</dd>
        </div>
        <div>
          <dt>Activity</dt>
          <dd>{@card.activity}</dd>
        </div>
      </dl>

      <div class="tt-public-card-actions">
        <.link navigate={@card.href} class="tt-public-card-link">Open branch</.link>
        <.link navigate={@card.seed_href} class="tt-public-card-link is-secondary">
          See {display_seed(@card.seed)}
        </.link>
      </div>
    </article>
    """
  end

  attr :card, :map, required: true
  attr :dom_prefix, :string, default: "notebook-card"

  def notebook_card(assigns) do
    ~H"""
    <article id={"#{@dom_prefix}-#{@card.id}"} class="tt-public-node-card" data-public-reveal>
      <div class="tt-public-node-card-head">
        <span class="tt-public-seed-chip">{@card.seed}</span>
        <span class="tt-public-node-meta">{@card.creator}</span>
      </div>

      <h3>{@card.title}</h3>
      <p>{@card.summary}</p>

      <dl class="tt-public-node-stats">
        <div>
          <dt>Stars</dt>
          <dd>{@card.stars}</dd>
        </div>
        <div>
          <dt>Watchers</dt>
          <dd>{@card.watchers}</dd>
        </div>
        <div>
          <dt>Notebook</dt>
          <dd>{@card.primary_file}</dd>
        </div>
        <div>
          <dt>Age</dt>
          <dd>{@card.age}</dd>
        </div>
      </dl>

      <div class="tt-public-card-actions">
        <.link navigate={@card.href} class="tt-public-card-link">View notebook details</.link>
        <.link navigate={@card.branch_href} class="tt-public-card-link is-secondary">
          Open branch
        </.link>
      </div>
    </article>
    """
  end

  attr :rows, :list, required: true
  attr :table_id, :string, default: "public-activity-table"

  def activity_table(assigns) do
    ~H"""
    <div class="tt-public-table-shell" data-public-reveal>
      <%= if @rows == [] do %>
        <div class="tt-public-empty-state">
          No public activity is visible yet. The next visible move will appear here.
        </div>
      <% else %>
        <table id={@table_id} class="tt-public-table">
          <thead>
            <tr>
              <th scope="col">Time</th>
              <th scope="col">Agent</th>
              <th scope="col">Action</th>
              <th scope="col">Subject</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{row, index} <- Enum.with_index(@rows, 1)} id={"#{@table_id}-row-#{index}"}>
              <td>{row.time}</td>
              <td>{row.agent}</td>
              <td>{row.action}</td>
              <td>
                <%= if row.href do %>
                  <.link navigate={row.href} class="tt-public-table-link">{row.subject}</.link>
                <% else %>
                  <span class="tt-public-table-link">{row.subject}</span>
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>
      <% end %>
    </div>
    """
  end

  attr :messages, :list, required: true
  attr :title, :string, required: true
  attr :copy, :string, required: true
  attr :room_id, :string, required: true

  def room_panel(assigns) do
    ~H"""
    <section id={@room_id} class="tt-public-room-panel" data-public-reveal>
      <div class="tt-public-room-head">
        <div>
          <h3>{@title}</h3>
          <p>{@copy}</p>
        </div>
        <span class="tt-public-room-count">{length(@messages)} recent</span>
      </div>

      <%= if @messages == [] do %>
        <div class="tt-public-empty-state">This room is quiet right now.</div>
      <% else %>
        <div class="tt-public-room-feed">
          <article
            :for={message <- @messages}
            id={"#{@room_id}-#{message.key}"}
            class="tt-public-room-entry"
          >
            <div class="tt-public-room-entry-top">
              <strong>{message.author}</strong>
              <span>{message.stamp}</span>
            </div>
            <p>{message.body}</p>
          </article>
        </div>
      <% end %>
    </section>
    """
  end

  attr :topic, :map, required: true

  def learn_card(assigns) do
    ~H"""
    <article id={"learn-card-#{@topic.id}"} class="tt-public-learn-card" data-public-reveal>
      <p class="tt-public-kicker">{@topic.label}</p>
      <h3>{@topic.title}</h3>
      <p>{@topic.summary}</p>
      <ul class="tt-public-bullet-list">
        <li :for={bullet <- @topic.bullets}>{bullet}</li>
      </ul>
      <div class="tt-public-card-actions">
        <.link navigate={@topic.href} class="tt-public-card-link">Read more</.link>
        <.link navigate={@topic.cta_href} class="tt-public-card-link is-secondary">
          {@topic.cta_label}
        </.link>
      </div>
    </article>
    """
  end

  defp kind_label(kind) when is_atom(kind),
    do: kind |> Atom.to_string() |> String.replace("_", " ")

  defp kind_label(kind) when is_binary(kind), do: String.replace(kind, "_", " ")
  defp kind_label(_kind), do: "node"

  defp display_seed("ML"), do: "Machine Learning"
  defp display_seed("Bioscience"), do: "Bioscience"
  defp display_seed("Polymarket"), do: "Polymarket"
  defp display_seed("DeFi"), do: "DeFi"
  defp display_seed("Firmware"), do: "Firmware"
  defp display_seed("Skills"), do: "Skills"
  defp display_seed("Evals"), do: "Evals"
  defp display_seed(seed), do: seed
end
