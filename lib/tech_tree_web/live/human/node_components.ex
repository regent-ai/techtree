defmodule TechTreeWeb.Human.NodeComponents do
  @moduledoc false
  use TechTreeWeb, :html

  alias TechTreeWeb.HumanComponents

  def not_found(assigns) do
    ~H"""
    <section class="tt-public-page-hero">
      <div class="tt-public-hero-copy" data-public-reveal>
        <p class="tt-public-kicker">Branch detail</p>
        <h1>Branch not found.</h1>
        <p class="tt-public-hero-copy-text">
          The requested node is unavailable or not publicly visible.
        </p>
        <div class="tt-public-hero-actions">
          <.link navigate={~p"/tree"} class="tt-public-primary-button">Back to tree</.link>
        </div>
      </div>
    </section>
    """
  end

  def node_page(assigns) do
    assigns =
      assigns
      |> assign(:node, assigns.page.node)
      |> assign(:autoskill, assigns.page.autoskill)
      |> assign(:cross_chain_lineage, assigns.page.cross_chain_lineage)

    ~H"""
    <section class="tt-public-hero tt-public-hero-split">
      <div class="tt-public-hero-copy" data-public-reveal>
        <p class="tt-public-kicker">Branch detail</p>
        <h1>{@node.title}</h1>
        <p class="tt-public-hero-copy-text">
          {@page.hero_summary}
        </p>

        <div class="tt-public-hero-actions">
          <.link navigate={~p"/tree"} class="tt-public-secondary-button">Tree</.link>
          <.link navigate={~p"/tree/seed/#{@node.seed}"} class="tt-public-secondary-button">
            Seed branches
          </.link>
          <.link
            :if={@page.parent}
            navigate={~p"/tree/node/#{@page.parent.id}"}
            class="tt-public-secondary-button"
          >
            Parent
          </.link>
          <.link
            id="node-branch-toggle"
            patch={~p"/tree/node/#{@node.id}"}
            class={["tt-public-secondary-button", @view == :branch && "is-active"]}
          >
            Branch view
          </.link>
          <.link
            id="node-graph-toggle"
            patch={~p"/tree/node/#{@node.id}?view=graph"}
            class={["tt-public-secondary-button", @view == :graph && "is-active"]}
          >
            Graph view
          </.link>
        </div>
      </div>

      <aside id="node-hero" class="tt-public-detail-card tt-public-stat-panel" data-public-reveal>
        <div class="tt-public-side-list-head">
          <h3>Overview</h3>
          <p>The core details that make this branch legible at a glance.</p>
        </div>
        <dl class="tt-public-node-stats tt-public-node-stats-large">
          <%= for row <- @page.overview_rows do %>
            <div>
              <dt>{row.label}</dt>
              <dd>{row.value}</dd>
            </div>
          <% end %>
        </dl>
      </aside>
    </section>

    <section
      :if={@view == :graph}
      id="node-graph"
      class="tt-public-detail-card tt-public-detail-card-wide"
    >
      <div class="tt-public-side-list-head">
        <h3>Local graph</h3>
        <p>See the lineage, focus node, and visible children in one compact view.</p>
      </div>
      <ol class="tt-public-graph-list">
        <%= for graph_node <- @page.graph_nodes do %>
          <li id={"node-graph-item-#{graph_node.id}"} class="tt-public-graph-node">
            <.link navigate={~p"/tree/node/#{graph_node.id}"} class="tt-public-graph-link">
              <span class="tt-public-node-meta">{graph_node.position}</span>
              <strong>{graph_node.title}</strong>
              <span>{HumanComponents.kind(graph_node.kind)}</span>
            </.link>
          </li>
        <% end %>
      </ol>
    </section>

    <section class="tt-public-node-detail-grid">
      <div class="tt-public-node-detail-main">
        <section id="node-proof" class="tt-public-detail-card">
          <div class="tt-public-side-list-head">
            <h3>Proof</h3>
            <p>Open the publication and notebook records that anchor this branch.</p>
          </div>
          <ul class="tt-public-detail-list">
            <%= for row <- @page.proof_rows do %>
              <li id={"node-proof-#{row.id}"}>
                <span>{row.label}</span>
                <strong>{row.value}</strong>
              </li>
            <% end %>
          </ul>
        </section>

        <section :if={@autoskill} id="node-autoskill" class="tt-public-detail-card">
          <div class="tt-public-side-list-head">
            <h3>Autoskill</h3>
            <p>{@autoskill.preview}</p>
          </div>
          <div class="tt-public-card-actions">
            <span :if={@autoskill.flavor_label} class="tt-public-room-chip">
              {@autoskill.flavor_label}
            </span>
            <span :if={@autoskill.mode_label} class="tt-public-room-chip">
              {@autoskill.mode_label}
            </span>
            <span :if={@autoskill.bundle_hash} class="tt-public-room-chip">
              Bundle {@autoskill.bundle_hash}
            </span>
          </div>
          <ul class="tt-public-detail-list">
            <li><span>Entrypoint</span><strong>{@autoskill.entrypoint}</strong></li>
            <li><span>Primary file</span><strong>{@autoskill.primary_file}</strong></li>
            <li><span>Access</span><strong>{@autoskill.access_copy}</strong></li>
            <li><span>Pull command</span><strong>{@autoskill.pull_command}</strong></li>
          </ul>
          <div :if={@autoskill.score_rows != []} class="tt-public-chip-row">
            <span :for={row <- @autoskill.score_rows} class="tt-public-room-chip">{row}</span>
          </div>
          <div :if={@autoskill.listing_rows != []} class="tt-public-chip-row">
            <span :for={row <- @autoskill.listing_rows} class="tt-public-room-chip">{row}</span>
          </div>
        </section>

        <section id="node-lineage" class="tt-public-detail-card">
          <div class="tt-public-side-list-head">
            <h3>Lineage</h3>
            <p>Move backward to the parent story or forward into visible children.</p>
          </div>

          <p :if={@page.parent} class="tt-public-detail-copy">
            Parent:
            <.link navigate={~p"/tree/node/#{@page.parent.id}"} class="tt-public-inline-link">
              {@page.parent.title}
            </.link>
          </p>

          <%= if @page.lineage == [] do %>
            <div class="hu-empty">This node is a seed root or has no visible lineage.</div>
          <% else %>
            <ol class="tt-public-inline-list">
              <%= for ancestor <- @page.lineage do %>
                <li id={"lineage-node-#{ancestor.id}"}>
                  <.link navigate={~p"/tree/node/#{ancestor.id}"} class="tt-public-inline-link">
                    {ancestor.title}
                  </.link>
                </li>
              <% end %>
            </ol>
          <% end %>

          <%= if @page.children == [] do %>
            <div class="hu-empty">No public children are attached to this node yet.</div>
          <% else %>
            <ul class="tt-public-detail-list">
              <%= for child <- @page.children do %>
                <li id={"child-node-#{child.id}"}>
                  <.link navigate={~p"/tree/node/#{child.id}"} class="tt-public-detail-link">
                    <span>{child.title}</span>
                    <strong>{HumanComponents.kind(child.kind)}</strong>
                  </.link>
                </li>
              <% end %>
            </ul>
          <% end %>
        </section>

        <section
          :if={@cross_chain_lineage}
          id="node-cross-chain-lineage"
          class="tt-public-detail-card"
        >
          <div class="tt-public-side-list-head">
            <h3>Cross-chain lineage</h3>
            <p>
              Track how this branch points to work on other chains when that history exists.
            </p>
          </div>

          <%= if @cross_chain_lineage.author_claim do %>
            <article class="tt-public-cross-chain-hero">
              <div class="tt-public-card-actions">
                <span class="tt-public-room-chip">Author claim</span>
                <span class="tt-public-room-chip">Most visible</span>
              </div>
              <h4>{@cross_chain_lineage.author_claim.relation_label}</h4>
              <p :if={@cross_chain_lineage.author_claim.target_label}>
                {@cross_chain_lineage.author_claim.target_label}
              </p>
              <p :if={@cross_chain_lineage.author_claim.note}>
                {@cross_chain_lineage.author_claim.note}
              </p>
            </article>
          <% end %>

          <%= if @cross_chain_lineage.summary_rows != [] do %>
            <dl class="tt-public-node-stats tt-public-node-stats-large">
              <%= for row <- @cross_chain_lineage.summary_rows do %>
                <div>
                  <dt>{row.label}</dt>
                  <dd>{row.value}</dd>
                </div>
              <% end %>
            </dl>
          <% end %>

          <%= if @cross_chain_lineage.claims == [] do %>
            <div class="hu-empty">No additional cross-chain claims are attached yet.</div>
          <% else %>
            <ol class="tt-public-claim-list">
              <%= for claim <- @cross_chain_lineage.claims do %>
                <li class="tt-public-claim-card">
                  <div class="tt-public-card-actions">
                    <span class="tt-public-room-chip">{claim.relation_label}</span>
                    <span :if={claim.claimant_label} class="tt-public-room-chip">
                      {claim.claimant_label}
                    </span>
                    <span :if={claim.declared_by_author} class="tt-public-room-chip">
                      Node author claim
                    </span>
                    <span :if={claim.mutual?} class="tt-public-room-chip">Mutual link</span>
                    <span :if={claim.disputed?} class="tt-public-room-chip">Disputed</span>
                  </div>
                  <p :if={claim.target_label}>{claim.target_label}</p>
                  <p :if={claim.note}>{claim.note}</p>
                </li>
              <% end %>
            </ol>
          <% end %>
        </section>

        <section id="node-discussion" class="tt-public-detail-card">
          <div class="tt-public-side-list-head">
            <h3>Discussion</h3>
            <p>See tagged neighbor branches and the public comment thread around this node.</p>
          </div>

          <%= if @page.related == [] do %>
            <div class="hu-empty">No tagged links were found for this node.</div>
          <% else %>
            <ul class="tt-public-detail-list">
              <%= for rel <- @page.related do %>
                <li id={"related-node-#{rel.dst_id}-#{rel.ordinal}"}>
                  <.link navigate={~p"/tree/node/#{rel.dst_id}"} class="tt-public-detail-link">
                    <span>{HumanComponents.present(rel.dst_title, "Node ##{rel.dst_id}")}</span>
                    <strong>{rel.tag}</strong>
                  </.link>
                </li>
              <% end %>
            </ul>
          <% end %>

          <%= if @page.comments == [] do %>
            <div class="hu-empty">No public comments yet.</div>
          <% else %>
            <ol class="tt-public-comment-list">
              <%= for comment <- @page.comments do %>
                <li id={"comment-#{comment.id}"} class="tt-public-comment-card">
                  <p>{comment.body_plaintext}</p>
                  <span>{comment.timestamp_label}</span>
                </li>
              <% end %>
            </ol>
          <% end %>
        </section>
      </div>

      <aside class="tt-public-node-detail-side">
        <section id="node-impact" class="tt-public-detail-card tt-public-stat-panel">
          <div class="tt-public-side-list-head">
            <h3>Impact</h3>
            <p>How much public follow-on work is already attached to this branch.</p>
          </div>
          <dl class="tt-public-node-stats tt-public-node-stats-large">
            <%= for row <- @page.impact_rows do %>
              <div>
                <dt>{row.label}</dt>
                <dd>{row.value}</dd>
              </div>
            <% end %>
          </dl>
        </section>

        <section id="node-monetization-provenance" class="tt-public-detail-card">
          <div class="tt-public-side-list-head">
            <h3>Monetization and provenance</h3>
            <p>
              The creator, chain, and publication details that explain where this node came from.
            </p>
          </div>
          <ul class="tt-public-detail-list">
            <%= for row <- @page.provenance_rows do %>
              <li id={"node-prov-#{row.id}"}>
                <span>{row.label}</span>
                <strong>{row.value}</strong>
              </li>
            <% end %>
          </ul>

          <%= if @page.provenance_links == [] do %>
            <div class="hu-empty">No explicit provenance or monetization links tagged yet.</div>
          <% else %>
            <ul class="tt-public-detail-list">
              <%= for rel <- @page.provenance_links do %>
                <li id={"provenance-node-#{rel.dst_id}-#{rel.ordinal}"}>
                  <.link navigate={~p"/tree/node/#{rel.dst_id}"} class="tt-public-detail-link">
                    <span>{HumanComponents.present(rel.dst_title, "Node ##{rel.dst_id}")}</span>
                    <strong>{rel.tag}</strong>
                  </.link>
                </li>
              <% end %>
            </ul>
          <% end %>
        </section>
      </aside>
    </section>
    """
  end
end
