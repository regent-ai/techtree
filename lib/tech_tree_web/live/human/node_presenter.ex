defmodule TechTreeWeb.Human.NodePresenter do
  @moduledoc false

  alias TechTree.HumanUX
  alias TechTreeWeb.HumanComponents

  @spec assign_page(Phoenix.LiveView.Socket.t(), HumanUX.node_page()) ::
          Phoenix.LiveView.Socket.t()
  def assign_page(socket, page) do
    display_page = build_page(page)

    socket
    |> Phoenix.Component.assign(:page_title, display_page.node.title)
    |> Phoenix.Component.assign(:not_found?, false)
    |> Phoenix.Component.assign(:page, display_page)
  end

  @spec assign_not_found(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def assign_not_found(socket) do
    socket
    |> Phoenix.Component.assign(:page_title, "Node not found")
    |> Phoenix.Component.assign(:not_found?, true)
    |> Phoenix.Component.assign(:page, nil)
  end

  @spec build_page(HumanUX.node_page()) :: map()
  def build_page(page) do
    %{
      node: page.node,
      parent: page.parent,
      lineage: page.lineage,
      children: page.children,
      related: page.related,
      comments:
        Enum.map(page.comments, &Map.put(&1, :timestamp_label, format_timestamp(&1.inserted_at))),
      hero_summary:
        HumanComponents.present(page.node.summary, "No summary available for this node."),
      overview_rows: overview_rows(page.node),
      graph_nodes: local_graph(page.lineage, page.node, page.children),
      proof_rows: proof_rows(page.node),
      autoskill: autoskill_panel(page.node),
      cross_chain_lineage: cross_chain_lineage(page.cross_chain_lineage),
      impact_rows: impact_rows(page.node),
      provenance_rows: provenance_rows(page.node),
      provenance_links: provenance_links(page.related)
    }
  end

  defp overview_rows(node) do
    [
      %{id: "id", label: "ID", value: Integer.to_string(node.id)},
      %{id: "type", label: "Type", value: HumanComponents.kind(node.kind)},
      %{id: "status", label: "Status", value: HumanComponents.kind(node.status)},
      %{id: "depth", label: "Depth", value: Integer.to_string(node.depth || 0)}
    ]
  end

  defp impact_rows(node) do
    [
      %{id: "children", label: "Children", value: Integer.to_string(node.child_count)},
      %{id: "comments", label: "Comments", value: Integer.to_string(node.comment_count)},
      %{id: "watchers", label: "Watchers", value: Integer.to_string(node.watcher_count)},
      %{id: "activity", label: "Activity", value: format_activity(node.activity_score)}
    ]
  end

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

  defp autoskill_panel(node) do
    if HumanComponents.autoskill?(node) do
      %{
        preview: autoskill_preview(node),
        flavor_label: HumanComponents.autoskill_flavor_label(node),
        mode_label: HumanComponents.autoskill_mode_label(node),
        bundle_hash: autoskill_bundle_hash(node),
        entrypoint: autoskill_entrypoint(node),
        primary_file: autoskill_primary_file(node),
        access_copy: autoskill_access_copy(node),
        pull_command: "regents techtree autoskill pull #{node.id}",
        score_rows: autoskill_score_rows(node),
        listing_rows: autoskill_listing_rows(node)
      }
    end
  end

  defp cross_chain_lineage(nil), do: nil

  defp cross_chain_lineage(lineage) do
    %{
      author_claim: lineage.author_claim,
      summary_rows: cross_chain_summary_rows(lineage),
      claims: Enum.take(lineage.claims, if(lineage.summary_mode, do: 6, else: 100))
    }
  end

  defp cross_chain_summary_rows(%{summary_mode: false}), do: []

  defp cross_chain_summary_rows(lineage) do
    [
      %{id: "claims", label: "Claims", value: lineage.summary.total},
      %{id: "author", label: "Author", value: lineage.summary.author_claims},
      %{id: "mutual", label: "Mutual", value: lineage.summary.mutual_claims},
      %{id: "disputed", label: "Disputed", value: lineage.summary.disputed_claims}
    ]
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
          position: "lineage"
        }
      end)

    current = %{
      id: node.id,
      title: node.title,
      kind: node.kind,
      position: "focus"
    }

    child_nodes =
      Enum.map(children, fn child ->
        %{
          id: child.id,
          title: child.title,
          kind: child.kind,
          position: "child"
        }
      end)

    lineage_nodes ++ [current] ++ child_nodes
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

  defp format_timestamp(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %-d, %Y %H:%M UTC")
  end

  defp format_timestamp(%NaiveDateTime{} = naive_datetime) do
    naive_datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> Calendar.strftime("%b %-d, %Y %H:%M UTC")
  end

  defp format_timestamp(_value), do: "Unknown timestamp"
end
