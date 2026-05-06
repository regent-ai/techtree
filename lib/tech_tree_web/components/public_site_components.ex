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
        %{key: :chat, label: "Public Room", href: "/chat"},
        %{key: :notebooks, label: "Notebook Gallery", href: "/notebooks"},
        %{key: :learn, label: "Research Systems", href: "/learn"},
        %{key: :benchmarks, label: "Benchmarks", href: "/benchmarks"},
        %{key: :bbh, label: "BBH", href: "/bbh"},
        %{key: :science_tasks, label: "Science Tasks", href: "/science-tasks"},
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
          aria-current={if(@current == item.key, do: "page", else: false)}
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

  def sigil(assigns) do
    ~H"""
    <span class="tt-public-sigil" aria-hidden="true">⩛</span>
    """
  end

  attr :kicker, :string, default: nil
  attr :title, :string, required: true
  attr :copy, :string, default: nil

  def section_heading(assigns) do
    ~H"""
    <div class="tt-public-section-head">
      <p :if={@kicker} class="tt-public-kicker"><.sigil /> {@kicker}</p>
      <h2>{@title}</h2>
      <p :if={@copy} class="tt-public-section-copy">{@copy}</p>
    </div>
    """
  end

  attr :items, :list, required: true
  attr :strip_id, :string, default: "public-signal-strip"

  def signal_strip(assigns) do
    ~H"""
    <div
      id={@strip_id}
      class="tt-public-signal-strip tt-public-live-panel"
      data-public-reveal
      data-public-live-panel={@strip_id}
    >
      <article
        :for={item <- @items}
        id={"#{@strip_id}-#{item.id}"}
        class="tt-public-signal-card tt-public-metric-card"
        data-public-metric-card={item.id}
        data-public-live-item={"#{@strip_id}-#{item.id}"}
        data-public-live-revision={item.value}
      >
        <p class="tt-public-signal-label">{item.label}</p>
        <%= if item.href do %>
          <.link navigate={item.href} class="tt-public-signal-value">{item.value}</.link>
        <% else %>
          <p class="tt-public-signal-value">{item.value}</p>
        <% end %>
        <p class="tt-public-signal-copy">{item.copy}</p>
      </article>
    </div>
    """
  end

  attr :messages, :list, required: true
  attr :panel_id, :string, required: true
  attr :title, :string, required: true
  attr :copy, :string, required: true

  def live_room_panel(assigns) do
    ~H"""
    <section id={@panel_id} class="tt-public-room-shell" data-public-reveal>
      <div class="tt-public-room-head">
        <div>
          <h3>{@title}</h3>
          <p>{@copy}</p>
        </div>
        <span class="tt-public-room-count">{length(@messages)} recent</span>
      </div>

      <%= if @messages == [] do %>
        <div class="tt-public-empty-state">
          The public room is quiet right now.
          <.link navigate={~p"/tree"} class="tt-public-inline-link">Open the live tree</.link>
          while the next message arrives.
        </div>
      <% else %>
        <div class="tt-public-room-feed">
          <article
            :for={message <- @messages}
            id={"#{@panel_id}-#{message.key}"}
            class="tt-public-room-entry tt-public-live-item"
            data-public-live-item={"#{@panel_id}-#{message.key}"}
            data-public-live-revision={message.key}
            data-public-live-kind="room-message"
          >
            <div class="tt-public-room-entry-top">
              <div class="tt-public-room-entry-copy">
                <strong>{message.author}</strong>
                <span class="tt-public-room-chip">{message.room}</span>
              </div>
              <span>{message.stamp}</span>
            </div>
            <p>{message.body}</p>
          </article>
        </div>
      <% end %>
    </section>
    """
  end

  attr :messages, :list, required: true
  attr :title, :string, required: true
  attr :copy, :string, required: true
  attr :room_id, :string, required: true

  def room_panel(assigns) do
    assigns = assign(assigns, :panel_id, assigns.room_id)
    live_room_panel(assigns)
  end

  attr :steps, :list, required: true
  attr :rail_id, :string, default: "public-step-rail"

  def step_rail(assigns) do
    ~H"""
    <ol id={@rail_id} class="tt-public-step-rail" data-public-reveal>
      <li :for={step <- @steps} id={"#{@rail_id}-#{step.id}"} class="tt-public-step-card">
        <span class="tt-public-step-index">{step_index(@steps, step.id)}</span>
        <div>
          <h3>{step.title}</h3>
          <p>{step.copy}</p>
        </div>
      </li>
    </ol>
    """
  end

  attr :steps, :list, required: true
  attr :loop_id, :string, default: "research-loop"
  attr :title, :string, default: "The loop"
  attr :copy, :string, default: nil

  def research_loop(assigns) do
    ~H"""
    <section id={@loop_id} class="tt-public-loop" data-public-reveal>
      <div class="tt-public-loop-head">
        <p class="tt-public-kicker"><.sigil /> Core loop</p>
        <h2>{@title}</h2>
        <p :if={@copy}>{@copy}</p>
      </div>

      <ol class="tt-public-loop-list">
        <li :for={step <- @steps} id={"#{@loop_id}-#{step.id}"} class="tt-public-loop-step">
          <span>{step_index(@steps, step.id)}</span>
          <div>
            <h3>{step.title}</h3>
            <p>{step.copy}</p>
          </div>
        </li>
      </ol>
    </section>
    """
  end

  attr :collections, :list, required: true
  attr :strip_id, :string, default: "notebook-collections"

  def collection_strip(assigns) do
    ~H"""
    <div id={@strip_id} class="tt-public-collection-strip" data-public-reveal>
      <article
        :for={collection <- @collections}
        id={"#{@strip_id}-#{collection.id}"}
        class="tt-public-collection-card"
      >
        <p class="tt-public-kicker">{collection.label}</p>
        <h3>{collection.title}</h3>
        <p>{collection.copy}</p>
        <div class="tt-public-card-actions">
          <span class="tt-public-room-chip">{collection.count} visible</span>
          <.link navigate={collection.href} class="tt-public-card-link is-secondary">
            Open branch
          </.link>
        </div>
      </article>
    </div>
    """
  end

  attr :items, :list, required: true
  attr :list_id, :string, required: true
  attr :title, :string, required: true

  def compact_link_list(assigns) do
    ~H"""
    <section id={@list_id} class="tt-public-side-list" data-public-reveal>
      <div class="tt-public-side-list-head">
        <h3>{@title}</h3>
      </div>

      <%= if @items == [] do %>
        <div class="tt-public-empty-state">
          Nothing public is visible here yet.
          <.link navigate={~p"/activity"} class="tt-public-inline-link">Open recent activity</.link>
          for the latest visible move.
        </div>
      <% else %>
        <ul class="tt-public-side-list-items">
          <li :for={item <- @items} id={"#{@list_id}-#{item.id}"}>
            <.link
              navigate={item.href}
              class="tt-public-side-link"
              data-public-live-item={"#{@list_id}-#{item.id}"}
              data-public-live-revision={item.meta}
              data-public-live-kind="public-list-item"
            >
              <div>
                <strong>{item.title}</strong>
                <p>{item.summary}</p>
              </div>
              <span>{item.meta}</span>
            </.link>
          </li>
        </ul>
      <% end %>
    </section>
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
    <article
      id={"#{@dom_prefix}-#{@card.id}"}
      class="tt-public-node-card tt-public-notebook-card"
      data-public-reveal
    >
      <div class="tt-public-notebook-preview" aria-hidden="true">
        <span class="tt-public-seed-chip">{@card.seed}</span>
        <span class="tt-public-node-meta">{@card.primary_file}</span>
      </div>

      <div class="tt-public-node-card-head">
        <span class="tt-public-room-chip">{@card.creator}</span>
        <span class="tt-public-node-meta">{@card.age}</span>
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
          <dd>{@card.marimo_entrypoint || "session.marimo.py"}</dd>
        </div>
        <div>
          <dt>Open from</dt>
          <dd>Branch detail</dd>
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
          No public activity is visible yet.
          <.link navigate={~p"/tree"} class="tt-public-inline-link">Open the live tree</.link>
          while the next visible move arrives.
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
            <tr
              :for={{row, index} <- Enum.with_index(@rows, 1)}
              id={"#{@table_id}-row-#{row.id || index}"}
              data-public-live-item={"#{@table_id}-row-#{row.id || index}"}
              data-public-live-revision={row.id || index}
              data-public-live-kind="activity-row"
            >
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

  attr :rows, :any, required: true
  attr :empty?, :boolean, default: false
  attr :table_id, :string, default: "public-activity-table"

  def activity_stream_table(assigns) do
    ~H"""
    <div class="tt-public-table-shell" data-public-reveal>
      <%= if @empty? do %>
        <div class="tt-public-empty-state">
          No public activity is visible yet.
          <.link navigate={~p"/tree"} class="tt-public-inline-link">Open the live tree</.link>
          while the next visible move arrives.
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
          <tbody id={"#{@table_id}-body"} phx-update="stream">
            <tr
              :for={{dom_id, row} <- @rows}
              id={dom_id}
              data-public-live-item={dom_id}
              data-public-live-revision={row.id}
              data-public-live-kind="activity-row"
            >
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

  attr :messages, :any, required: true
  attr :message_count, :integer, required: true
  attr :empty?, :boolean, default: false
  attr :panel_id, :string, required: true
  attr :title, :string, required: true
  attr :copy, :string, required: true

  def live_room_stream_panel(assigns) do
    ~H"""
    <section id={@panel_id} class="tt-public-room-shell" data-public-reveal>
      <div class="tt-public-room-head">
        <div>
          <h3>{@title}</h3>
          <p>{@copy}</p>
        </div>
        <span class="tt-public-room-count">{@message_count} recent</span>
      </div>

      <%= if @empty? do %>
        <div class="tt-public-empty-state">
          The public room is quiet right now.
          <.link navigate={~p"/activity"} class="tt-public-inline-link">Check recent activity</.link>
          while the next message arrives.
        </div>
      <% else %>
        <div id={"#{@panel_id}-feed"} class="tt-public-room-feed" phx-update="stream">
          <article
            :for={{dom_id, message} <- @messages}
            id={dom_id}
            class="tt-public-room-entry tt-public-live-item"
            data-public-live-item={dom_id}
            data-public-live-revision={message.key}
            data-public-live-kind="room-message"
          >
            <div class="tt-public-room-entry-top">
              <div class="tt-public-room-entry-copy">
                <strong>{message.author}</strong>
                <span class="tt-public-room-chip">{message.room}</span>
              </div>
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

  defp step_index(steps, step_id) do
    steps
    |> Enum.find_index(&(&1.id == step_id))
    |> case do
      nil -> "00"
      index -> (index + 1) |> Integer.to_string() |> String.pad_leading(2, "0")
    end
  end
end
