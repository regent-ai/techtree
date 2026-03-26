defmodule TechTree.Autoskill do
  @moduledoc """
  Autoskill bundles, eval scenarios, scored results, reviews, and listings.
  """

  import Ecto.Query
  import Ecto.Changeset, only: [add_error: 3, get_field: 2]

  alias TechTree.Agents.AgentIdentity
  alias TechTree.Autoskill.{Listing, NodeBundle, Result, Review}
  alias TechTree.IPFS.{Digests, LighthouseClient}
  alias TechTree.Nodes
  alias TechTree.Nodes.Node
  alias TechTree.Payments
  alias TechTree.Repo

  @listing_threshold 10

  def create_skill_version(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    create_bundle_backed_node(agent, :skill, attrs)
  end

  def create_eval_version(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    create_bundle_backed_node(agent, :eval, attrs)
  end

  def publish_result(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    with {:ok, skill} <- fetch_node_kind(attrs["skill_node_id"] || attrs[:skill_node_id], :skill),
         {:ok, eval} <- fetch_node_kind(attrs["eval_node_id"] || attrs[:eval_node_id], :eval),
         :ok <- ensure_bundle_type(skill.id, :skill),
         :ok <- ensure_bundle_type(eval.id, :eval) do
      %Result{}
      |> Result.changeset(Map.put(attrs, "executor_agent_id", agent.id))
      |> Repo.insert()
    end
  end

  def create_review(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    with {:ok, skill} <- fetch_node_kind(attrs["skill_node_id"] || attrs[:skill_node_id], :skill),
         :ok <- ensure_bundle_type(skill.id, :skill),
         :ok <- validate_review_result(attrs, skill.id) do
      %Review{}
      |> Review.changeset(Map.put(attrs, "reviewer_agent_id", agent.id))
      |> Repo.insert()
    end
  end

  def list_skill_versions(slug) when is_binary(slug) do
    anchored_nodes_query()
    |> where([node, _agent], node.kind == :skill and node.skill_slug == ^String.trim(slug))
    |> order_by([node, _agent], desc: node.inserted_at)
    |> Repo.all()
    |> Repo.preload(:creator_agent)
    |> attach_projection()
  end

  def list_eval_versions(slug) when is_binary(slug) do
    anchored_nodes_query()
    |> where([node, _agent], node.kind == :eval and node.slug == ^String.trim(slug))
    |> order_by([node, _agent], desc: node.inserted_at)
    |> Repo.all()
    |> Repo.preload(:creator_agent)
    |> attach_projection()
  end

  def list_reviews(skill_node_id) do
    skill_node_id
    |> normalize_id()
    |> then(fn id ->
      Review
      |> where([review], review.skill_node_id == ^id)
      |> order_by([review], desc: review.inserted_at)
      |> Repo.all()
    end)
  end

  def list_results(skill_node_id, eval_node_id \\ nil) do
    skill_node_id = normalize_id(skill_node_id)

    query =
      Result
      |> where([result], result.skill_node_id == ^skill_node_id)
      |> order_by([result], desc: result.inserted_at)

    query =
      if is_nil(eval_node_id) do
        query
      else
        where(query, [result], result.eval_node_id == ^normalize_id(eval_node_id))
      end

    Repo.all(query)
  end

  def version_scorecard(skill_node_id) do
    [scorecard] = scorecards_for_skill_ids([normalize_id(skill_node_id)])
    scorecard
  end

  def eligible_for_listing?(skill_node_id) do
    skill = Repo.get!(Node, normalize_id(skill_node_id))
    count = distinct_replicable_review_count(skill.id, skill.creator_agent_id)
    count >= @listing_threshold
  end

  def create_listing(%AgentIdentity{} = agent, skill_node_id, attrs) when is_map(attrs) do
    with {:ok, skill} <- fetch_node_kind(skill_node_id, :skill),
         :ok <- ensure_bundle_type(skill.id, :skill),
         true <- eligible_for_listing?(skill.id),
         {:ok, listing_attrs} <- normalize_listing_attrs(attrs, skill.id, agent.id) do
      %Listing{}
      |> Listing.changeset(listing_attrs)
      |> validate_listing_chain()
      |> Repo.insert()
    else
      false -> {:error, :replicable_review_threshold_not_met}
      {:error, reason} -> {:error, reason}
      %Ecto.Changeset{} = changeset -> {:error, changeset}
    end
  end

  def get_listing(skill_node_id) do
    case Repo.get_by(Listing, skill_node_id: normalize_id(skill_node_id)) do
      nil -> nil
      listing -> encode_listing(listing)
    end
  end

  def fetch_bundle_for_access(node_id, access_ctx) do
    bundle = Repo.get_by!(NodeBundle, node_id: normalize_id(node_id))

    case bundle.access_mode do
      :public_free ->
        {:ok, bundle}

      :gated_paid ->
        verify_receipt(bundle, access_ctx)
        |> case do
          :ok -> {:ok, bundle}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def encode_version_summary(%Node{} = node) do
    autoskill = node.autoskill || %{}

    %{
      node_id: node.id,
      kind: Atom.to_string(node.kind),
      seed: node.seed,
      slug: node.slug,
      title: node.title,
      summary: node.summary,
      inserted_at: node.inserted_at,
      creator_agent:
        if(Ecto.assoc_loaded?(node.creator_agent) and node.creator_agent,
          do: %{
            id: node.creator_agent.id,
            label: node.creator_agent.label,
            wallet_address: node.creator_agent.wallet_address
          },
          else: nil
        ),
      autoskill: autoskill
    }
  end

  def encode_review(%Review{} = review) do
    %{
      id: review.id,
      kind: enum_to_string(review.kind),
      skill_node_id: review.skill_node_id,
      reviewer_agent_id: review.reviewer_agent_id,
      result_id: review.result_id,
      rating: review.rating,
      note: review.note,
      runtime_kind: enum_to_string(review.runtime_kind),
      reported_score: review.reported_score,
      details: review.details || %{},
      inserted_at: review.inserted_at
    }
  end

  def attach_projection([]), do: []

  def attach_projection(%Node{} = node) do
    case attach_projection([node]) do
      [projected] -> projected
      _ -> node
    end
  end

  def attach_projection(nodes) when is_list(nodes) do
    node_ids =
      nodes
      |> Enum.map(& &1.id)
      |> Enum.reject(&is_nil/1)

    bundles_by_node_id =
      NodeBundle
      |> where([bundle], bundle.node_id in ^node_ids)
      |> Repo.all()
      |> Map.new(&{&1.node_id, &1})

    scorecards_by_skill_id =
      nodes
      |> Enum.filter(&(&1.kind == :skill and Map.has_key?(bundles_by_node_id, &1.id)))
      |> Enum.map(& &1.id)
      |> scorecards_for_skill_ids()
      |> Map.new(fn scorecard ->
        {scorecard.skill_node_id, Map.delete(scorecard, :skill_node_id)}
      end)

    listings_by_skill_id =
      Listing
      |> where([listing], listing.skill_node_id in ^node_ids)
      |> Repo.all()
      |> Map.new(fn listing -> {listing.skill_node_id, encode_listing(listing)} end)

    Enum.map(nodes, fn node ->
      autoskill =
        case Map.get(bundles_by_node_id, node.id) do
          nil ->
            nil

          bundle ->
            build_projection(
              node,
              bundle,
              scorecards_by_skill_id[node.id],
              listings_by_skill_id[node.id]
            )
        end

      %{node | autoskill: autoskill}
    end)
  end

  defp create_bundle_backed_node(agent, kind, attrs) do
    Repo.transaction(fn ->
      with {:ok, parent_id} <- resolve_parent_id(kind, attrs),
           {:ok, node_attrs} <- build_node_attrs(kind, attrs, parent_id),
           {:ok, %Node{} = node} <- Nodes.create_agent_node(agent, node_attrs),
           {:ok, %NodeBundle{} = bundle} <- create_bundle(node, kind, attrs) do
        %{node: attach_projection(node), bundle: bundle}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp resolve_parent_id(kind, attrs) do
    seed = seed_for(kind)

    case attrs["parent_id"] || attrs[:parent_id] do
      nil ->
        {:ok, Nodes.create_seed_root!(seed, seed).id}

      parent_id ->
        normalized = normalize_id(parent_id)

        case Repo.get(Node, normalized) do
          %Node{seed: ^seed} -> {:ok, normalized}
          %Node{} -> {:error, :invalid_autoskill_parent}
          nil -> {:error, :parent_not_found}
        end
    end
  end

  defp build_node_attrs(:skill, attrs, parent_id) do
    skill_slug = required_text(attrs, "skill_slug")
    skill_version = required_text(attrs, "skill_version")
    title = required_text(attrs, "title")
    summary = optional_text(attrs, "summary")
    preview_md = optional_text(attrs, "preview_md") || "# Preview only"

    with {:ok, skill_slug} <- require_value(skill_slug, :skill_slug_required),
         {:ok, skill_version} <- require_value(skill_version, :skill_version_required),
         {:ok, title} <- require_value(title, :title_required) do
      {:ok,
       %{
         "seed" => "Skills",
         "kind" => "skill",
         "parent_id" => parent_id,
         "title" => title,
         "summary" => summary,
         "slug" => optional_text(attrs, "slug") || skill_slug,
         "skill_slug" => skill_slug,
         "skill_version" => skill_version,
         "notebook_source" =>
           optional_text(attrs, "notebook_source") || preview_notebook(title, preview_md),
         "skill_md_body" => preview_md
       }}
    end
  end

  defp build_node_attrs(:eval, attrs, parent_id) do
    title = required_text(attrs, "title")
    slug = required_text(attrs, "slug")

    with {:ok, title} <- require_value(title, :title_required),
         {:ok, slug} <- require_value(slug, :slug_required) do
      {:ok,
       %{
         "seed" => "Evals",
         "kind" => "eval",
         "parent_id" => parent_id,
         "title" => title,
         "summary" => optional_text(attrs, "summary"),
         "slug" => slug,
         "notebook_source" =>
           optional_text(attrs, "notebook_source") ||
             preview_notebook(title, optional_text(attrs, "preview_md"))
       }}
    end
  end

  defp create_bundle(node, kind, attrs) do
    uploaded_bundle_attrs = maybe_upload_bundle_archive(attrs)

    %NodeBundle{}
    |> NodeBundle.changeset(%{
      node_id: node.id,
      bundle_type: kind,
      access_mode: attrs["access_mode"] || attrs[:access_mode],
      preview_md: optional_text(attrs, "preview_md"),
      bundle_manifest: attrs["bundle_manifest"] || attrs[:bundle_manifest],
      primary_file: optional_text(attrs, "primary_file"),
      marimo_entrypoint: attrs["marimo_entrypoint"] || attrs[:marimo_entrypoint],
      bundle_uri:
        Map.get(uploaded_bundle_attrs, :bundle_uri) || optional_text(attrs, "bundle_uri"),
      bundle_cid:
        Map.get(uploaded_bundle_attrs, :bundle_cid) || optional_text(attrs, "bundle_cid"),
      bundle_hash:
        Map.get(uploaded_bundle_attrs, :bundle_hash) || optional_text(attrs, "bundle_hash"),
      encrypted_bundle_uri:
        Map.get(uploaded_bundle_attrs, :encrypted_bundle_uri) ||
          optional_text(attrs, "encrypted_bundle_uri"),
      encrypted_bundle_cid:
        Map.get(uploaded_bundle_attrs, :encrypted_bundle_cid) ||
          optional_text(attrs, "encrypted_bundle_cid"),
      encryption_meta: attrs["encryption_meta"] || attrs[:encryption_meta],
      payment_rail: attrs["payment_rail"] || attrs[:payment_rail],
      access_policy: attrs["access_policy"] || attrs[:access_policy]
    })
    |> Repo.insert()
  end

  defp verify_receipt(%NodeBundle{payment_rail: :x402} = bundle, access_ctx),
    do: Payments.X402.verify_access(bundle, access_ctx)

  defp verify_receipt(%NodeBundle{payment_rail: :mpp} = bundle, access_ctx),
    do: Payments.MPP.verify_access(bundle, access_ctx)

  defp verify_receipt(_bundle, _access_ctx), do: {:error, :payment_required}

  defp build_projection(node, bundle, scorecard, listing) do
    %{
      flavor: Atom.to_string(bundle.bundle_type),
      access_mode: Atom.to_string(bundle.access_mode),
      preview_md: bundle.preview_md,
      marimo_entrypoint: bundle.marimo_entrypoint,
      primary_file: bundle.primary_file,
      bundle_hash: bundle.bundle_hash,
      scorecard: scorecard,
      listing: if(node.kind == :skill, do: listing, else: nil)
    }
  end

  defp scorecards_for_skill_ids([]) do
    []
  end

  defp scorecards_for_skill_ids(skill_ids) do
    community =
      Review
      |> where([review], review.skill_node_id in ^skill_ids and review.kind == :community)
      |> group_by([review], review.skill_node_id)
      |> select([review], %{
        skill_node_id: review.skill_node_id,
        count: count(review.id),
        avg_rating: avg(review.rating)
      })
      |> Repo.all()
      |> Map.new(&{&1.skill_node_id, &1})

    replicable =
      Review
      |> join(:inner, [review], result in Result, on: result.id == review.result_id)
      |> where(
        [review, _result],
        review.skill_node_id in ^skill_ids and review.kind == :replicable
      )
      |> group_by([review, _result], review.skill_node_id)
      |> select([review, result], %{
        skill_node_id: review.skill_node_id,
        review_count: count(review.id),
        unique_agent_count: count(fragment("distinct ?", review.reviewer_agent_id)),
        median_score:
          fragment("percentile_cont(0.5) within group (order by ?)", result.normalized_score)
      })
      |> Repo.all()
      |> Map.new(&{&1.skill_node_id, &1})

    Enum.map(skill_ids, fn skill_id ->
      %{
        skill_node_id: skill_id,
        community: %{
          count: (community[skill_id] && community[skill_id].count) || 0,
          avg_rating: community[skill_id] && community[skill_id].avg_rating
        },
        replicable: %{
          review_count: (replicable[skill_id] && replicable[skill_id].review_count) || 0,
          unique_agent_count:
            (replicable[skill_id] && replicable[skill_id].unique_agent_count) || 0,
          median_score: replicable[skill_id] && replicable[skill_id].median_score
        }
      }
    end)
  end

  defp distinct_replicable_review_count(skill_node_id, creator_id) do
    Review
    |> where(
      [review],
      review.skill_node_id == ^skill_node_id and review.kind == :replicable and
        review.reviewer_agent_id != ^creator_id
    )
    |> select([review], count(fragment("distinct ?", review.reviewer_agent_id)))
    |> Repo.one()
  end

  defp validate_review_result(attrs, skill_node_id) do
    case attrs["kind"] || attrs[:kind] do
      kind when kind in ["replicable", :replicable] ->
        result_id = attrs["result_id"] || attrs[:result_id]

        with {:ok, normalized_result_id} <- normalize_id_safe(result_id) do
          case Repo.get(Result, normalized_result_id) do
            %Result{skill_node_id: ^skill_node_id} -> :ok
            %Result{} -> {:error, :autoskill_result_skill_mismatch}
            nil -> {:error, :autoskill_result_not_found}
          end
        end

      _ ->
        :ok
    end
  end

  defp normalize_listing_attrs(attrs, skill_node_id, seller_agent_id) do
    {:ok,
     %{
       "skill_node_id" => skill_node_id,
       "seller_agent_id" => seller_agent_id,
       "payment_rail" => attrs["payment_rail"] || attrs[:payment_rail],
       "chain_id" => attrs["chain_id"] || attrs[:chain_id],
       "usdc_token_address" => attrs["usdc_token_address"] || attrs[:usdc_token_address],
       "treasury_address" => attrs["treasury_address"] || attrs[:treasury_address],
       "seller_payout_address" => attrs["seller_payout_address"] || attrs[:seller_payout_address],
       "price_usdc" => attrs["price_usdc"] || attrs[:price_usdc],
       "treasury_bps" => 100,
       "seller_bps" => 9900,
       "listing_meta" => attrs["listing_meta"] || attrs[:listing_meta] || %{}
     }}
  end

  defp validate_listing_chain(%Ecto.Changeset{} = changeset) do
    case get_field(changeset, :chain_id) do
      chain_id when is_integer(chain_id) ->
        with {:ok, config} <- chain_config(chain_id),
             :ok <-
               ensure_matches_config(changeset, :usdc_token_address, config.usdc_token_address),
             :ok <- ensure_matches_config(changeset, :treasury_address, config.treasury_address) do
          changeset
        else
          {:error, reason} -> add_error(changeset, :chain_id, Atom.to_string(reason))
        end

      _ ->
        changeset
    end
  end

  defp ensure_matches_config(changeset, field, expected) do
    actual = get_field(changeset, field)

    cond do
      not is_binary(expected) or String.trim(expected) == "" ->
        {:error, :autoskill_chain_not_configured}

      is_binary(actual) and String.downcase(actual) == String.downcase(expected) ->
        :ok

      true ->
        {:error, :autoskill_chain_mismatch}
    end
  end

  defp fetch_node_kind(node_id, expected_kind) do
    case Repo.get(Node, normalize_id(node_id)) do
      %Node{kind: ^expected_kind} = node -> {:ok, node}
      %Node{} -> {:error, :autoskill_invalid_node_kind}
      nil -> {:error, :node_not_found}
    end
  end

  defp ensure_bundle_type(node_id, expected_type) do
    case Repo.get_by(NodeBundle, node_id: normalize_id(node_id)) do
      %NodeBundle{bundle_type: ^expected_type} -> :ok
      %NodeBundle{} -> {:error, :autoskill_bundle_type_mismatch}
      nil -> {:error, :autoskill_bundle_not_found}
    end
  end

  defp chain_config(chain_id) do
    config = Application.get_env(:tech_tree, :autoskill, [])

    case Keyword.get(config, :chains, %{}) do
      %{^chain_id => chain_config} ->
        {:ok, normalize_chain_config(chain_config)}

      chain_map when is_map(chain_map) ->
        case Map.get(chain_map, chain_id) || Map.get(chain_map, Integer.to_string(chain_id)) do
          nil -> {:error, :autoskill_chain_unsupported}
          value -> {:ok, normalize_chain_config(value)}
        end

      _ ->
        {:error, :autoskill_chain_unsupported}
    end
  end

  defp normalize_chain_config(config) when is_list(config) do
    %{
      settlement_contract_address: Keyword.get(config, :settlement_contract_address),
      usdc_token_address: Keyword.get(config, :usdc_token_address),
      treasury_address: Keyword.get(config, :treasury_address)
    }
  end

  defp normalize_chain_config(config) when is_map(config) do
    %{
      settlement_contract_address:
        Map.get(
          config,
          :settlement_contract_address,
          Map.get(config, "settlement_contract_address")
        ),
      usdc_token_address:
        Map.get(config, :usdc_token_address, Map.get(config, "usdc_token_address")),
      treasury_address: Map.get(config, :treasury_address, Map.get(config, "treasury_address"))
    }
  end

  defp normalize_chain_config(_config) do
    %{
      settlement_contract_address: nil,
      usdc_token_address: nil,
      treasury_address: nil
    }
  end

  defp encode_listing(%Listing{} = listing) do
    settlement_contract_address =
      case chain_config(listing.chain_id) do
        {:ok, config} -> config.settlement_contract_address
        _ -> nil
      end

    %{
      id: listing.id,
      skill_node_id: listing.skill_node_id,
      seller_agent_id: listing.seller_agent_id,
      status: Atom.to_string(listing.status),
      payment_rail: Atom.to_string(listing.payment_rail),
      chain_id: listing.chain_id,
      settlement_contract_address: settlement_contract_address,
      usdc_token_address: listing.usdc_token_address,
      treasury_address: listing.treasury_address,
      seller_payout_address: listing.seller_payout_address,
      price_usdc: listing.price_usdc,
      treasury_bps: listing.treasury_bps,
      seller_bps: listing.seller_bps,
      listing_meta: listing.listing_meta || %{},
      inserted_at: listing.inserted_at,
      updated_at: listing.updated_at
    }
  end

  defp preview_notebook(title, preview_md) do
    """
    import marimo as mo
    app = mo.App()

    @app.cell
    def _():
        title = #{inspect(title)}
        preview = #{inspect(preview_md || "")}
        return title, preview

    if __name__ == "__main__":
        app.run()
    """
  end

  defp seed_for(:skill), do: "Skills"
  defp seed_for(:eval), do: "Evals"

  defp require_value(nil, error), do: {:error, error}
  defp require_value(value, _error), do: {:ok, value}

  defp maybe_upload_bundle_archive(attrs) do
    access_mode = attrs["access_mode"] || attrs[:access_mode]

    case access_mode do
      "public_free" ->
        archive_upload_attrs(
          attrs["bundle_archive_b64"] || attrs[:bundle_archive_b64],
          "autoskill-bundle.json"
        )

      :public_free ->
        archive_upload_attrs(
          attrs["bundle_archive_b64"] || attrs[:bundle_archive_b64],
          "autoskill-bundle.json"
        )

      "gated_paid" ->
        archive_upload_attrs(
          attrs["encrypted_bundle_archive_b64"] || attrs[:encrypted_bundle_archive_b64],
          "autoskill-bundle.encrypted.json"
        )

      :gated_paid ->
        archive_upload_attrs(
          attrs["encrypted_bundle_archive_b64"] || attrs[:encrypted_bundle_archive_b64],
          "autoskill-bundle.encrypted.json"
        )

      _ ->
        %{}
    end
  end

  defp archive_upload_attrs(nil, _filename), do: %{}

  defp archive_upload_attrs(encoded_archive, filename) when is_binary(encoded_archive) do
    archive_bytes = Base.decode64!(encoded_archive)

    upload =
      LighthouseClient.upload_content!(filename, archive_bytes, content_type: "application/json")

    attrs = %{
      bundle_hash: Digests.sha256_hex(archive_bytes)
    }

    if String.contains?(filename, ".encrypted.") do
      Map.merge(attrs, %{
        encrypted_bundle_uri: "ipfs://#{upload.cid}",
        encrypted_bundle_cid: upload.cid
      })
    else
      Map.merge(attrs, %{
        bundle_uri: "ipfs://#{upload.cid}",
        bundle_cid: upload.cid
      })
    end
  end

  defp required_text(attrs, key), do: optional_text(attrs, key)

  defp optional_text(attrs, key) do
    case Map.get(attrs, to_string(key), Map.get(attrs, key)) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  defp normalize_id(value) when is_integer(value), do: value
  defp normalize_id(value) when is_binary(value), do: String.to_integer(String.trim(value))

  defp normalize_id_safe(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp normalize_id_safe(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> {:error, :autoskill_result_not_found}
    end
  end

  defp normalize_id_safe(_value), do: {:error, :autoskill_result_not_found}

  defp anchored_nodes_query do
    Node
    |> join(:inner, [node], agent in AgentIdentity, on: agent.id == node.creator_agent_id)
    |> where([node, agent], node.status == :anchored and agent.status == "active")
  end

  defp enum_to_string(nil), do: nil
  defp enum_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_to_string(value) when is_binary(value), do: value
end
