defmodule TechTree.Autoskill do
  @moduledoc """
  Autoskill bundles, eval scenarios, scored results, reviews, and listings.
  """

  import Ecto.Query

  alias TechTree.Agents.AgentIdentity

  alias TechTree.Autoskill.{
    BundleNodes,
    Listing,
    Listings,
    NodeBundle,
    Projection,
    Result,
    Review
  }

  alias TechTree.NodeAccess
  alias TechTree.Nodes
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  def create_skill_version(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    create_bundle_backed_node(agent, :skill, attrs)
  end

  def create_eval_version(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    create_bundle_backed_node(agent, :eval, attrs)
  end

  def publish_result(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    with {:ok, skill} <-
           Listings.fetch_node_kind(attrs["skill_node_id"], :skill),
         {:ok, eval} <-
           Listings.fetch_node_kind(attrs["eval_node_id"], :eval),
         :ok <- Listings.ensure_bundle_type(skill.id, :skill),
         :ok <- Listings.ensure_bundle_type(eval.id, :eval) do
      %Result{}
      |> Result.changeset(Map.put(attrs, "executor_agent_id", agent.id))
      |> Repo.insert()
    end
  end

  def create_review(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    with {:ok, skill} <-
           Listings.fetch_node_kind(attrs["skill_node_id"], :skill),
         :ok <- Listings.ensure_bundle_type(skill.id, :skill),
         :ok <- Listings.validate_review_result(attrs, skill.id) do
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
    |> Projection.attach_projection()
  end

  def list_eval_versions(slug) when is_binary(slug) do
    anchored_nodes_query()
    |> where([node, _agent], node.kind == :eval and node.slug == ^String.trim(slug))
    |> order_by([node, _agent], desc: node.inserted_at)
    |> Repo.all()
    |> Repo.preload(:creator_agent)
    |> Projection.attach_projection()
  end

  def list_reviews(skill_node_id) do
    skill_node_id
    |> Listings.normalize_id()
    |> then(fn id ->
      Review
      |> where([review], review.skill_node_id == ^id)
      |> order_by([review], desc: review.inserted_at)
      |> Repo.all()
    end)
  end

  def list_results(skill_node_id, eval_node_id \\ nil) do
    skill_node_id = Listings.normalize_id(skill_node_id)

    query =
      Result
      |> where([result], result.skill_node_id == ^skill_node_id)
      |> order_by([result], desc: result.inserted_at)

    query =
      if is_nil(eval_node_id) do
        query
      else
        where(query, [result], result.eval_node_id == ^Listings.normalize_id(eval_node_id))
      end

    Repo.all(query)
  end

  def version_scorecard(skill_node_id) do
    [scorecard] = Projection.scorecards_for_skill_ids([Listings.normalize_id(skill_node_id)])
    scorecard
  end

  def eligible_for_listing?(skill_node_id) do
    Listings.eligible_for_listing?(skill_node_id)
  end

  def create_listing(%AgentIdentity{} = agent, skill_node_id, attrs) when is_map(attrs) do
    with {:ok, skill} <- Listings.fetch_node_kind(skill_node_id, :skill),
         :ok <- Listings.ensure_bundle_type(skill.id, :skill),
         :ok <- ensure_skill_creator(skill, agent),
         true <- Listings.eligible_for_listing?(skill.id),
         {:ok, listing_attrs} <- Listings.normalize_listing_attrs(attrs, skill.id, agent.id) do
      Repo.transaction(fn ->
        with {:ok, listing} <-
               %Listing{}
               |> Listing.changeset(listing_attrs)
               |> Listings.validate_listing_chain()
               |> Repo.insert(),
             {:ok, _payload} <- NodeAccess.activate_from_listing(listing) do
          listing
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    else
      false -> {:error, :replicable_review_threshold_not_met}
      {:error, reason} -> {:error, reason}
      %Ecto.Changeset{} = changeset -> {:error, changeset}
    end
  end

  defp ensure_skill_creator(%Node{creator_agent_id: agent_id}, %AgentIdentity{id: agent_id}),
    do: :ok

  defp ensure_skill_creator(%Node{}, %AgentIdentity{}),
    do: {:error, :autoskill_listing_creator_required}

  def get_listing(skill_node_id) do
    case Repo.get_by(Listing, skill_node_id: Listings.normalize_id(skill_node_id)) do
      nil -> nil
      listing -> Listings.encode_listing(listing)
    end
  end

  def fetch_bundle_for_access(node_id, _access_ctx) do
    bundle = Repo.get_by!(NodeBundle, node_id: Listings.normalize_id(node_id))

    case bundle.access_mode do
      :public_free ->
        {:ok, bundle}

      :gated_paid ->
        {:error, :payment_required}
    end
  end

  def fetch_bundle_for_agent_access(node_id, %AgentIdentity{} = agent) do
    bundle = Repo.get_by!(NodeBundle, node_id: Listings.normalize_id(node_id))

    case bundle.access_mode do
      :public_free ->
        {:ok, bundle}

      :gated_paid ->
        with {:ok, _download} <- NodeAccess.fetch_payload_for_agent(node_id, agent) do
          {:ok, bundle}
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

  def attach_projection(nodes), do: Projection.attach_projection(nodes)

  defp create_bundle_backed_node(agent, kind, attrs) do
    Repo.transaction(fn ->
      with {:ok, parent_id} <- BundleNodes.resolve_parent_id(kind, attrs),
           {:ok, node_attrs} <- BundleNodes.build_node_attrs(kind, attrs, parent_id),
           {:ok, %Node{} = node} <- Nodes.create_agent_node(agent, node_attrs),
           {:ok, %NodeBundle{} = bundle} <- BundleNodes.create_bundle(node, kind, attrs),
           {:ok, _payload} <- NodeAccess.sync_autoskill_bundle(node, agent, bundle) do
        %{node: Projection.attach_projection(node), bundle: bundle}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp anchored_nodes_query do
    Node
    |> join(:inner, [node], agent in AgentIdentity, on: agent.id == node.creator_agent_id)
    |> where([node, agent], node.status == :anchored and agent.status == "active")
  end

  defp enum_to_string(nil), do: nil
  defp enum_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_to_string(value) when is_binary(value), do: value
end
