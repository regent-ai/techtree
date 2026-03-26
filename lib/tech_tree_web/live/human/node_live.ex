defmodule TechTreeWeb.Human.NodeLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  import TechTreeWeb.HumanComponents

  alias TechTree.HumanUX
  alias TechTreeWeb.HumanComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket = assign(socket, :view, :branch)

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
    <main
      id="human-node-page"
      class="hu-page"
      phx-hook="HumanMotion"
      data-motion-scope="node"
      data-motion-view={Atom.to_string(@view)}
    >
      <div class="hu-shell">
        <%= if @not_found? do %>
          <.human_header
            kicker="Node"
            title="Node not found"
            subtitle="The requested node is unavailable or not publicly visible."
          >
            <:actions>
              <.link navigate={~p"/"} class="hu-primary-link">Back to seeds</.link>
            </:actions>
          </.human_header>
        <% else %>
          <.human_header
            kicker={@node.seed}
            title={@node.title}
            subtitle={HumanComponents.present(@node.summary, "No summary available for this node.")}
          >
            <:actions>
              <.link navigate={~p"/"} class="hu-ghost-link">Seeds</.link>
              <.link navigate={~p"/seed/#{@node.seed}"} class="hu-ghost-link">Seed branches</.link>
              <.link :if={@parent} navigate={~p"/node/#{@parent.id}"} class="hu-toggle-link">
                Parent
              </.link>
              <.link
                id="node-branch-toggle"
                patch={~p"/node/#{@node.id}"}
                class={HumanComponents.toggle_class(@view == :branch)}
              >
                Branch
              </.link>
              <.link
                id="node-graph-toggle"
                patch={~p"/node/#{@node.id}?view=graph"}
                class={HumanComponents.toggle_class(@view == :graph)}
              >
                Graph
              </.link>
            </:actions>
          </.human_header>

          <.human_section id="node-hero" title="Hero">
            <p class="hu-seed-summary">
              {HumanComponents.present(@node.summary, "No summary available for this node.")}
            </p>
            <dl class="hu-stat-grid hu-stat-grid-wide">
              <.human_stat label="ID" value={Integer.to_string(@node.id)} />
              <.human_stat label="Type" value={HumanComponents.kind(@node.kind)} />
              <.human_stat label="Status" value={HumanComponents.kind(@node.status)} />
              <.human_stat label="Depth" value={Integer.to_string(@node.depth || 0)} />
            </dl>
          </.human_section>

          <%= if @view == :graph do %>
            <.human_section id="node-graph" title="Local graph">
              <ol class="hu-graph-list">
                <%= for graph_node <- local_graph(@lineage, @node, @children) do %>
                  <li
                    id={"node-graph-item-#{graph_node.id}"}
                    class="hu-graph-node"
                    style={"--hu-depth: #{graph_node.depth}"}
                    data-motion="graph-node"
                  >
                    <.link navigate={~p"/node/#{graph_node.id}"} class="hu-graph-link">
                      <span class="hu-graph-kind">{graph_node.position}</span>
                      <span class="hu-graph-title">{graph_node.title}</span>
                      <span class="hu-graph-meta">{HumanComponents.kind(graph_node.kind)}</span>
                    </.link>
                  </li>
                <% end %>
              </ol>
            </.human_section>
          <% end %>

          <.human_section id="node-proof" title="Proof">
            <ul class="hu-list">
              <%= for row <- proof_rows(@node) do %>
                <li id={"node-proof-#{row.id}"}>
                  <div class="hu-list-link">
                    <span>{row.label}</span>
                    <span class="hu-list-meta">{row.value}</span>
                  </div>
                </li>
              <% end %>
            </ul>
          </.human_section>

          <.human_section :if={autoskill_panel?(@node)} id="node-autoskill" title="Autoskill">
            <div class="hu-autoskill-panel">
              <div class="hu-autoskill-row">
                <span class="hu-autoskill-chip">{HumanComponents.autoskill_flavor_label(@node)}</span>
                <span :if={HumanComponents.autoskill_mode_label(@node)} class="hu-list-meta">
                  {HumanComponents.autoskill_mode_label(@node)}
                </span>
                <span :if={autoskill_bundle_hash(@node)} class="hu-list-meta">
                  Bundle {autoskill_bundle_hash(@node)}
                </span>
              </div>

              <p class="hu-seed-summary">{autoskill_preview(@node)}</p>

              <dl class="hu-stat-grid hu-stat-grid-wide">
                <.human_stat label="Entrypoint" value={autoskill_entrypoint(@node)} />
                <.human_stat label="Primary file" value={autoskill_primary_file(@node)} />
                <.human_stat label="Access" value={autoskill_access_copy(@node)} />
                <.human_stat
                  label="Pull command"
                  value={"regent techtree autoskill pull #{@node.id}"}
                />
              </dl>

              <%= if autoskill_score_rows(@node) != [] do %>
                <div class="hu-autoskill-strip">
                  <%= for row <- autoskill_score_rows(@node) do %>
                    <span class="hu-lineage-chip">{row}</span>
                  <% end %>
                </div>
              <% end %>

              <%= if autoskill_listing_rows(@node) != [] do %>
                <div class="hu-autoskill-strip">
                  <%= for row <- autoskill_listing_rows(@node) do %>
                    <span class="hu-lineage-chip">{row}</span>
                  <% end %>
                </div>
              <% end %>
            </div>
          </.human_section>

          <.human_section id="node-lineage" title="Lineage">
            <%= if @parent do %>
              <p class="hu-seed-summary">
                Parent:
                <.link navigate={~p"/node/#{@parent.id}"} class="hu-inline-link">
                  {@parent.title}
                </.link>
              </p>
            <% end %>

            <%= if @lineage == [] do %>
              <.empty_state message="This node is a seed root or has no visible lineage." />
            <% else %>
              <ol class="hu-inline-list">
                <%= for ancestor <- @lineage do %>
                  <li id={"lineage-node-#{ancestor.id}"}>
                    <.link navigate={~p"/node/#{ancestor.id}"} class="hu-inline-link">
                      {ancestor.title}
                    </.link>
                  </li>
                <% end %>
              </ol>
            <% end %>

            <%= if @children == [] do %>
              <.empty_state message="No public children are attached to this node yet." />
            <% else %>
              <ul class="hu-list">
                <%= for child <- @children do %>
                  <li id={"child-node-#{child.id}"}>
                    <.link navigate={~p"/node/#{child.id}"} class="hu-list-link">
                      <span>{child.title}</span>
                      <span class="hu-list-meta">{HumanComponents.kind(child.kind)}</span>
                    </.link>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </.human_section>

          <.human_section
            :if={@cross_chain_lineage}
            id="node-cross-chain-lineage"
            title="Cross-chain lineage"
          >
            <%= if @cross_chain_lineage.author_claim do %>
              <article class="hu-lineage-hero" data-motion="reveal">
                <div class="hu-lineage-hero-head">
                  <p class="hu-lineage-kicker">Author claim</p>
                  <span class="hu-lineage-chip">Most visible</span>
                </div>

                <p class="hu-lineage-hero-relation">
                  {@cross_chain_lineage.author_claim.relation_label}
                  <%= if @cross_chain_lineage.author_claim.target_label do %>
                    <span class="hu-lineage-chip">
                      {@cross_chain_lineage.author_claim.target_label}
                    </span>
                  <% end %>
                </p>

                <p :if={@cross_chain_lineage.author_claim.note} class="hu-lineage-note">
                  {@cross_chain_lineage.author_claim.note}
                </p>

                <div class="hu-lineage-meta-row">
                  <span :if={@cross_chain_lineage.author_claim.claimant_label} class="hu-lineage-chip">
                    {@cross_chain_lineage.author_claim.claimant_label}
                  </span>
                  <span
                    :if={@cross_chain_lineage.author_claim.declared_by_author}
                    class="hu-lineage-chip"
                  >
                    Declared by node author
                  </span>
                </div>
              </article>
            <% end %>

            <%= if @cross_chain_lineage.summary_mode do %>
              <div class="hu-lineage-summary" data-motion="reveal">
                <dl class="hu-stat-grid hu-stat-grid-wide">
                  <.human_stat
                    label="Claims"
                    value={Integer.to_string(@cross_chain_lineage.summary.total)}
                  />
                  <.human_stat
                    label="Author"
                    value={Integer.to_string(@cross_chain_lineage.summary.author_claims)}
                  />
                  <.human_stat
                    label="Mutual"
                    value={Integer.to_string(@cross_chain_lineage.summary.mutual_claims)}
                  />
                  <.human_stat
                    label="Disputed"
                    value={Integer.to_string(@cross_chain_lineage.summary.disputed_claims)}
                  />
                </dl>

                <div
                  :if={@cross_chain_lineage.summary.relation_buckets != []}
                  class="hu-lineage-chart"
                >
                  <%= for bucket <- @cross_chain_lineage.summary.relation_buckets do %>
                    <div class="hu-lineage-bar" data-motion="graph-node">
                      <div class="hu-lineage-bar-head">
                        <span>{bucket.label}</span>
                        <span>{bucket.count}</span>
                      </div>
                      <div class="hu-lineage-bar-track" aria-hidden="true">
                        <span
                          class="hu-lineage-bar-fill"
                          data-motion="score-bar"
                          style={"width: #{bucket.percent}%"}
                        />
                      </div>
                    </div>
                  <% end %>
                </div>

                <p class="hu-seed-summary">
                  Showing a compact summary because this node has a large lineage claim set.
                </p>
              </div>
            <% end %>

            <%= if @cross_chain_lineage.claims == [] do %>
              <.empty_state message="No additional cross-chain claims are attached yet." />
            <% else %>
              <ol class="hu-lineage-claim-list">
                <%= for claim <- Enum.take(@cross_chain_lineage.claims, @cross_chain_lineage.summary_mode && 6 || 100) do %>
                  <li
                    class={[
                      "hu-lineage-claim",
                      claim.declared_by_author && "hu-lineage-claim--author"
                    ]}
                    data-motion="graph-node"
                  >
                    <div class="hu-lineage-claim-head">
                      <span class="hu-lineage-claim-relation">{claim.relation_label}</span>
                      <span :if={claim.claimant_label} class="hu-lineage-chip">
                        {claim.claimant_label}
                      </span>
                    </div>

                    <div class="hu-lineage-meta-row">
                      <span :if={claim.target_label} class="hu-lineage-chip">
                        {claim.target_label}
                      </span>
                      <span :if={claim.declared_by_author} class="hu-lineage-chip">
                        Node author claim
                      </span>
                      <span :if={claim.mutual?} class="hu-lineage-chip">Mutual link</span>
                      <span :if={claim.disputed?} class="hu-lineage-chip">Disputed</span>
                    </div>

                    <p :if={claim.note} class="hu-lineage-note">{claim.note}</p>
                  </li>
                <% end %>
              </ol>

              <p :if={@cross_chain_lineage.summary_mode} class="hu-seed-summary">
                The full claim stream is collapsed into this summary view to keep the page legible.
              </p>
            <% end %>
          </.human_section>

          <.human_section id="node-impact" title="Impact">
            <dl class="hu-stat-grid hu-stat-grid-wide">
              <.human_stat label="Children" value={Integer.to_string(@node.child_count)} />
              <.human_stat label="Comments" value={Integer.to_string(@node.comment_count)} />
              <.human_stat label="Watchers" value={Integer.to_string(@node.watcher_count)} />
              <.human_stat label="Activity" value={format_activity(@node.activity_score)} />
            </dl>
          </.human_section>

          <.human_section id="node-discussion" title="Discussion">
            <%= if @related == [] do %>
              <.empty_state message="No tagged links were found for this node." />
            <% else %>
              <ul class="hu-list">
                <%= for rel <- @related do %>
                  <li id={"related-node-#{rel.dst_id}-#{rel.ordinal}"}>
                    <.link navigate={~p"/node/#{rel.dst_id}"} class="hu-list-link">
                      <span>{HumanComponents.present(rel.dst_title, "Node ##{rel.dst_id}")}</span>
                      <span class="hu-list-meta">{rel.tag}</span>
                    </.link>
                  </li>
                <% end %>
              </ul>
            <% end %>

            <%= if @comments == [] do %>
              <.empty_state message="No public comments yet." />
            <% else %>
              <ol class="hu-comment-list">
                <%= for comment <- @comments do %>
                  <li id={"comment-#{comment.id}"} class="hu-comment-item">
                    <p>{comment.body_plaintext}</p>
                    <span class="hu-comment-meta">{format_timestamp(comment.inserted_at)}</span>
                  </li>
                <% end %>
              </ol>
            <% end %>
          </.human_section>

          <.human_section id="node-monetization-provenance" title="Monetization / provenance">
            <ul class="hu-list">
              <%= for row <- provenance_rows(@node) do %>
                <li id={"node-prov-#{row.id}"}>
                  <div class="hu-list-link">
                    <span>{row.label}</span>
                    <span class="hu-list-meta">{row.value}</span>
                  </div>
                </li>
              <% end %>
            </ul>

            <% links = provenance_links(@related) %>
            <%= if links == [] do %>
              <.empty_state message="No explicit provenance or monetization links tagged yet." />
            <% else %>
              <ul class="hu-list">
                <%= for rel <- links do %>
                  <li id={"provenance-node-#{rel.dst_id}-#{rel.ordinal}"}>
                    <.link navigate={~p"/node/#{rel.dst_id}"} class="hu-list-link">
                      <span>{HumanComponents.present(rel.dst_title, "Node ##{rel.dst_id}")}</span>
                      <span class="hu-list-meta">{rel.tag}</span>
                    </.link>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </.human_section>
        <% end %>
      </div>
    </main>
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

  defp autoskill_listing_rows(%{autoskill: %{listing: listing}}) when is_map(listing) do
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
      end
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp autoskill_listing_rows(_node), do: []

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
