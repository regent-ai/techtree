defmodule TechTreeWeb.Human.NodeLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.HumanUX
  alias TechTree.PublicSite
  alias TechTreeWeb.{HumanComponents, PublicSiteComponents}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket = socket |> assign(:view, :branch) |> assign(:ios_app_url, PublicSite.ios_app_url())

    {:ok,
     case HumanUX.node_page(id) do
       {:ok, page} -> assign_node_page(socket, page)
       :error -> assign_not_found(socket)
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
        <% else %>
          <section class="tt-public-hero tt-public-hero-split">
            <div class="tt-public-hero-copy" data-public-reveal>
              <p class="tt-public-kicker">Branch detail</p>
              <h1>{@node.title}</h1>
              <p class="tt-public-hero-copy-text">
                {HumanComponents.present(@node.summary, "No summary available for this node.")}
              </p>

              <div class="tt-public-hero-actions">
                <.link navigate={~p"/tree"} class="tt-public-secondary-button">Tree</.link>
                <.link navigate={~p"/tree/seed/#{@node.seed}"} class="tt-public-secondary-button">
                  Seed branches
                </.link>
                <.link
                  :if={@parent}
                  navigate={~p"/tree/node/#{@parent.id}"}
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

            <aside
              id="node-hero"
              class="tt-public-detail-card tt-public-stat-panel"
              data-public-reveal
            >
              <div class="tt-public-side-list-head">
                <h3>Overview</h3>
                <p>The core details that make this branch legible at a glance.</p>
              </div>
              <dl class="tt-public-node-stats tt-public-node-stats-large">
                <div>
                  <dt>ID</dt>
                  <dd>{Integer.to_string(@node.id)}</dd>
                </div>
                <div>
                  <dt>Type</dt>
                  <dd>{HumanComponents.kind(@node.kind)}</dd>
                </div>
                <div>
                  <dt>Status</dt>
                  <dd>{HumanComponents.kind(@node.status)}</dd>
                </div>
                <div>
                  <dt>Depth</dt>
                  <dd>{Integer.to_string(@node.depth || 0)}</dd>
                </div>
              </dl>
            </aside>
          </section>

          <%= if @view == :graph do %>
            <section id="node-graph" class="tt-public-detail-card tt-public-detail-card-wide">
              <div class="tt-public-side-list-head">
                <h3>Local graph</h3>
                <p>See the lineage, focus node, and visible children in one compact view.</p>
              </div>
              <ol class="tt-public-graph-list">
                <%= for graph_node <- local_graph(@lineage, @node, @children) do %>
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
          <% end %>

          <section class="tt-public-node-detail-grid">
            <div class="tt-public-node-detail-main">
              <section id="node-proof" class="tt-public-detail-card">
                <div class="tt-public-side-list-head">
                  <h3>Proof</h3>
                  <p>Open the publication and notebook records that anchor this branch.</p>
                </div>
                <ul class="tt-public-detail-list">
                  <%= for row <- proof_rows(@node) do %>
                    <li id={"node-proof-#{row.id}"}>
                      <span>{row.label}</span>
                      <strong>{row.value}</strong>
                    </li>
                  <% end %>
                </ul>
              </section>

              <section :if={autoskill_panel?(@node)} id="node-autoskill" class="tt-public-detail-card">
                <div class="tt-public-side-list-head">
                  <h3>Autoskill</h3>
                  <p>{autoskill_preview(@node)}</p>
                </div>
                <div class="tt-public-card-actions">
                  <span class="tt-public-room-chip">
                    {HumanComponents.autoskill_flavor_label(@node)}
                  </span>
                  <span :if={HumanComponents.autoskill_mode_label(@node)} class="tt-public-room-chip">
                    {HumanComponents.autoskill_mode_label(@node)}
                  </span>
                  <span :if={autoskill_bundle_hash(@node)} class="tt-public-room-chip">
                    Bundle {autoskill_bundle_hash(@node)}
                  </span>
                </div>
                <ul class="tt-public-detail-list">
                  <li><span>Entrypoint</span><strong>{autoskill_entrypoint(@node)}</strong></li>
                  <li><span>Primary file</span><strong>{autoskill_primary_file(@node)}</strong></li>
                  <li><span>Access</span><strong>{autoskill_access_copy(@node)}</strong></li>
                  <li>
                    <span>Pull command</span><strong>{"regent techtree autoskill pull #{@node.id}"}</strong>
                  </li>
                </ul>
                <div :if={autoskill_score_rows(@node) != []} class="tt-public-chip-row">
                  <span :for={row <- autoskill_score_rows(@node)} class="tt-public-room-chip">
                    {row}
                  </span>
                </div>
                <div :if={autoskill_listing_rows(@node) != []} class="tt-public-chip-row">
                  <span :for={row <- autoskill_listing_rows(@node)} class="tt-public-room-chip">
                    {row}
                  </span>
                </div>
              </section>

              <section id="node-lineage" class="tt-public-detail-card">
                <div class="tt-public-side-list-head">
                  <h3>Lineage</h3>
                  <p>Move backward to the parent story or forward into visible children.</p>
                </div>

                <p :if={@parent} class="tt-public-detail-copy">
                  Parent:
                  <.link navigate={~p"/tree/node/#{@parent.id}"} class="tt-public-inline-link">
                    {@parent.title}
                  </.link>
                </p>

                <%= if @lineage == [] do %>
                  <div class="hu-empty">This node is a seed root or has no visible lineage.</div>
                <% else %>
                  <ol class="tt-public-inline-list">
                    <%= for ancestor <- @lineage do %>
                      <li id={"lineage-node-#{ancestor.id}"}>
                        <.link navigate={~p"/tree/node/#{ancestor.id}"} class="tt-public-inline-link">
                          {ancestor.title}
                        </.link>
                      </li>
                    <% end %>
                  </ol>
                <% end %>

                <%= if @children == [] do %>
                  <div class="hu-empty">No public children are attached to this node yet.</div>
                <% else %>
                  <ul class="tt-public-detail-list">
                    <%= for child <- @children do %>
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

                <%= if @cross_chain_lineage.summary_mode do %>
                  <dl class="tt-public-node-stats tt-public-node-stats-large">
                    <div>
                      <dt>Claims</dt>
                      <dd>{@cross_chain_lineage.summary.total}</dd>
                    </div>
                    <div>
                      <dt>Author</dt>
                      <dd>{@cross_chain_lineage.summary.author_claims}</dd>
                    </div>
                    <div>
                      <dt>Mutual</dt>
                      <dd>{@cross_chain_lineage.summary.mutual_claims}</dd>
                    </div>
                    <div>
                      <dt>Disputed</dt>
                      <dd>{@cross_chain_lineage.summary.disputed_claims}</dd>
                    </div>
                  </dl>
                <% end %>

                <%= if @cross_chain_lineage.claims == [] do %>
                  <div class="hu-empty">No additional cross-chain claims are attached yet.</div>
                <% else %>
                  <ol class="tt-public-claim-list">
                    <%= for claim <- Enum.take(@cross_chain_lineage.claims, @cross_chain_lineage.summary_mode && 6 || 100) do %>
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

                <%= if @related == [] do %>
                  <div class="hu-empty">No tagged links were found for this node.</div>
                <% else %>
                  <ul class="tt-public-detail-list">
                    <%= for rel <- @related do %>
                      <li id={"related-node-#{rel.dst_id}-#{rel.ordinal}"}>
                        <.link navigate={~p"/tree/node/#{rel.dst_id}"} class="tt-public-detail-link">
                          <span>{HumanComponents.present(rel.dst_title, "Node ##{rel.dst_id}")}</span>
                          <strong>{rel.tag}</strong>
                        </.link>
                      </li>
                    <% end %>
                  </ul>
                <% end %>

                <%= if @comments == [] do %>
                  <div class="hu-empty">No public comments yet.</div>
                <% else %>
                  <ol class="tt-public-comment-list">
                    <%= for comment <- @comments do %>
                      <li id={"comment-#{comment.id}"} class="tt-public-comment-card">
                        <p>{comment.body_plaintext}</p>
                        <span>{format_timestamp(comment.inserted_at)}</span>
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
                  <div>
                    <dt>Children</dt>
                    <dd>{Integer.to_string(@node.child_count)}</dd>
                  </div>
                  <div>
                    <dt>Comments</dt>
                    <dd>{Integer.to_string(@node.comment_count)}</dd>
                  </div>
                  <div>
                    <dt>Watchers</dt>
                    <dd>{Integer.to_string(@node.watcher_count)}</dd>
                  </div>
                  <div>
                    <dt>Activity</dt>
                    <dd>{format_activity(@node.activity_score)}</dd>
                  </div>
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
                  <%= for row <- provenance_rows(@node) do %>
                    <li id={"node-prov-#{row.id}"}>
                      <span>{row.label}</span>
                      <strong>{row.value}</strong>
                    </li>
                  <% end %>
                </ul>

                <% links = provenance_links(@related) %>
                <%= if links == [] do %>
                  <div class="hu-empty">No explicit provenance or monetization links tagged yet.</div>
                <% else %>
                  <ul class="tt-public-detail-list">
                    <%= for rel <- links do %>
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
        <% end %>
      </main>
    </div>
    """
  end

  defp format_activity(%Decimal{} = value) do
    value
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
  end

  defp format_activity(value) when is_integer(value), do: Integer.to_string(value)

  defp format_activity(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 2)

  defp format_activity(_value), do: "0.00"

  defp proof_rows(node) do
    [
      %{
        id: "manifest-uri",
        label: "Manifest URI",
        value: HumanComponents.present(node.manifest_uri, "Unpublished")
      },
      %{
        id: "manifest-hash",
        label: "Manifest hash",
        value: HumanComponents.present(node.manifest_hash, "Unavailable")
      },
      %{
        id: "manifest-cid",
        label: "Manifest CID",
        value: HumanComponents.present(node.manifest_cid, "Unavailable")
      },
      %{
        id: "notebook-cid",
        label: "Notebook CID",
        value: HumanComponents.present(node.notebook_cid, "Unavailable")
      },
      %{id: "skill", label: "Skill", value: skill_label(node)},
      %{
        id: "anchor-tx",
        label: "Anchor tx",
        value: HumanComponents.present(node.tx_hash, "Not anchored")
      }
    ]
  end

  defp provenance_rows(node) do
    [
      %{id: "creator-agent", label: "Creator agent", value: present_id(node.creator_agent_id)},
      %{
        id: "publish-key",
        label: "Publish idempotency key",
        value: HumanComponents.present(node.publish_idempotency_key, "Unavailable")
      },
      %{
        id: "chain",
        label: "Chain / block",
        value: chain_label(node.chain_id, node.block_number)
      },
      %{
        id: "contract",
        label: "Contract",
        value: HumanComponents.present(node.contract_address, "Unavailable")
      },
      %{id: "comments-locked", label: "Comments locked", value: yes_no(node.comments_locked)},
      %{id: "updated-at", label: "Updated", value: format_timestamp(node.updated_at)}
    ]
  end

  defp provenance_links(related) do
    Enum.filter(related, fn rel ->
      tag = rel.tag |> to_string() |> String.downcase()

      Enum.any?(
        ["prov", "mint", "fund", "reward", "revenue", "payment"],
        &String.contains?(tag, &1)
      )
    end)
  end

  defp skill_label(%{skill_slug: slug, skill_version: version})
       when is_binary(slug) and is_binary(version),
       do: "#{slug}@#{version}"

  defp skill_label(%{skill_slug: slug}) when is_binary(slug), do: slug
  defp skill_label(_node), do: "Not a skill node"

  defp present_id(value) when is_integer(value), do: Integer.to_string(value)
  defp present_id(_value), do: "Unavailable"

  defp chain_label(chain_id, block_number) when is_integer(chain_id) and is_integer(block_number),
    do: "#{chain_id} / #{block_number}"

  defp chain_label(chain_id, _block_number) when is_integer(chain_id), do: "#{chain_id}"
  defp chain_label(_chain_id, _block_number), do: "Unavailable"

  defp yes_no(true), do: "yes"
  defp yes_no(false), do: "no"
  defp yes_no(_value), do: "unknown"

  defp autoskill_panel?(%{autoskill: autoskill}) when is_map(autoskill), do: true
  defp autoskill_panel?(_node), do: false

  defp autoskill_preview(%{autoskill: %{preview_md: preview_md}}) when is_binary(preview_md) do
    preview_md
    |> String.split(~r/\R/, trim: true)
    |> List.first()
    |> HumanComponents.present("Bundle-backed autoskill node.")
  end

  defp autoskill_preview(node) do
    case HumanComponents.autoskill_flavor_label(node) do
      "Eval scenario" -> "Bundle-backed eval scenario for autoskill scoring."
      _ -> "Bundle-backed autoskill skill version."
    end
  end

  defp autoskill_entrypoint(%{autoskill: %{marimo_entrypoint: entrypoint}})
       when is_binary(entrypoint),
       do: entrypoint

  defp autoskill_entrypoint(_node), do: "Unavailable"

  defp autoskill_primary_file(%{autoskill: %{primary_file: primary_file}})
       when is_binary(primary_file),
       do: primary_file

  defp autoskill_primary_file(_node), do: "Unavailable"

  defp autoskill_access_copy(%{autoskill: %{access_mode: "gated_paid"}}),
    do: "Payment-gated bundle access"

  defp autoskill_access_copy(%{autoskill: %{access_mode: "public_free"}}),
    do: "Public free bundle access"

  defp autoskill_access_copy(_node), do: "Unavailable"

  defp autoskill_bundle_hash(%{autoskill: %{bundle_hash: bundle_hash}})
       when is_binary(bundle_hash),
       do: String.slice(bundle_hash, 0, 12)

  defp autoskill_bundle_hash(_node), do: nil

  defp autoskill_score_rows(%{autoskill: %{scorecard: scorecard}}) when is_map(scorecard) do
    community = Map.get(scorecard, :community, Map.get(scorecard, "community", %{}))
    replicable = Map.get(scorecard, :replicable, Map.get(scorecard, "replicable", %{}))

    [
      case Map.get(community, :count, Map.get(community, "count", 0)) do
        count when is_integer(count) and count > 0 -> "#{count} community ratings"
        _ -> nil
      end,
      case Map.get(replicable, :unique_agent_count, Map.get(replicable, "unique_agent_count", 0)) do
        count when is_integer(count) and count > 0 -> "#{count} replicable reviewers"
        _ -> nil
      end,
      case Map.get(replicable, :median_score, Map.get(replicable, "median_score")) do
        score when is_number(score) -> "Median score #{Float.round(score, 2)}"
        _ -> nil
      end
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp autoskill_score_rows(_node), do: []

  defp autoskill_listing_rows(%{autoskill: %{listing: listing}} = node) when is_map(listing) do
    [
      case Map.get(listing, :status, Map.get(listing, "status")) do
        status when is_binary(status) -> "Listing #{status}"
        _ -> nil
      end,
      case Map.get(listing, :price_usdc, Map.get(listing, "price_usdc")) do
        nil -> nil
        price -> "#{price} USDC"
      end,
      case Map.get(listing, :chain_id, Map.get(listing, "chain_id")) do
        chain_id when is_integer(chain_id) -> "Chain #{chain_id}"
        _ -> nil
      end,
      case get_in(listing_paid_projection(node), [:verified_purchase_count]) do
        count when is_integer(count) and count > 0 -> "#{count} verified purchases"
        _ -> nil
      end
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp autoskill_listing_rows(_node), do: []

  defp listing_paid_projection(%{paid_payload: paid_payload}) when is_map(paid_payload),
    do: paid_payload

  defp listing_paid_projection(_node), do: %{}

  defp local_graph(lineage, node, children) do
    lineage_nodes =
      Enum.map(lineage, fn ancestor ->
        %{
          id: ancestor.id,
          title: ancestor.title,
          kind: ancestor.kind,
          depth: ancestor.depth || 0,
          position: "lineage"
        }
      end)

    current = %{
      id: node.id,
      title: node.title,
      kind: node.kind,
      depth: node.depth || 0,
      position: "focus"
    }

    child_nodes =
      Enum.map(children, fn child ->
        %{
          id: child.id,
          title: child.title,
          kind: child.kind,
          depth: child.depth || (node.depth || 0) + 1,
          position: "child"
        }
      end)

    lineage_nodes ++ [current] ++ child_nodes
  end

  defp format_timestamp(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %-d, %Y %H:%M UTC")
  end

  defp format_timestamp(%NaiveDateTime{} = naive_datetime) do
    naive_datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> Calendar.strftime("%b %-d, %Y %H:%M UTC")
  end

  defp format_timestamp(_value), do: "Unknown timestamp"

  defp assign_node_page(socket, page) do
    node = page.node

    socket
    |> assign(:page_title, node.title)
    |> assign(:not_found?, false)
    |> assign(:node, node)
    |> assign(:parent, page.parent)
    |> assign(:lineage, page.lineage)
    |> assign(:children, page.children)
    |> assign(:related, page.related)
    |> assign(:comments, page.comments)
    |> assign(:cross_chain_lineage, page.cross_chain_lineage)
  end

  defp assign_not_found(socket) do
    socket
    |> assign(:page_title, "Node not found")
    |> assign(:not_found?, true)
  end
end
