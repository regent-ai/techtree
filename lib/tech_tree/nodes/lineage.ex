defmodule TechTree.Nodes.Lineage do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Changeset
  alias TechTree.{Chains, Repo}
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Nodes.{Node, NodeCrossChainLink, NodeLineageClaim}

  @type projection :: %{
          status: String.t(),
          author_claim: map() | nil,
          claims: [map()]
        }

  @spec attach_projection(Node.t()) :: Node.t()
  def attach_projection(%Node{} = node) do
    %{node | cross_chain_lineage: projection(node)}
  end

  @spec projection(Node.t()) :: projection() | nil
  def projection(%Node{} = node) do
    author_link = active_author_link(node.id)
    claims = active_claims(node.id)

    case {author_link, claims} do
      {nil, []} ->
        nil

      _ ->
        author_claim =
          case author_link do
            nil ->
              nil

            link ->
              encode_author_link(link, mutually_linked?(node, link), disputed?(link, claims))
          end

        encoded_claims =
          Enum.map(claims, fn claim ->
            encode_claim(claim, author_link, claims)
          end)

        %{
          status: projection_status(author_link, claims, author_claim),
          author_claim: author_claim,
          claims: encoded_claims
        }
    end
  end

  @spec list_links(Node.t()) :: [NodeCrossChainLink.t()]
  def list_links(%Node{} = node) do
    NodeCrossChainLink
    |> where([link], link.node_id == ^node.id)
    |> order_by([link], desc: link.inserted_at, desc: link.id)
    |> Repo.all()
    |> preload_link_assocs()
  end

  @spec list_claims(Node.t()) :: [NodeLineageClaim.t()]
  def list_claims(%Node{} = node) do
    NodeLineageClaim
    |> where([claim], claim.subject_node_id == ^node.id)
    |> order_by([claim], desc: claim.inserted_at, desc: claim.id)
    |> Repo.all()
    |> preload_claim_assocs()
  end

  @spec create_claim(Node.t(), AgentIdentity.t(), map()) ::
          {:ok, NodeLineageClaim.t()} | {:error, term()}
  def create_claim(%Node{} = subject_node, %AgentIdentity{} = claimant, attrs) do
    with {:ok, normalized} <- normalize_subject_attrs(attrs),
         {:ok, normalized} <- validate_target_node(normalized) do
      %NodeLineageClaim{}
      |> NodeLineageClaim.changeset(
        Map.merge(normalized, %{
          subject_node_id: subject_node.id,
          claimant_agent_id: claimant.id
        })
      )
      |> Repo.insert()
      |> maybe_preload_claim()
    end
  end

  @spec withdraw_claim(Node.t(), integer(), AgentIdentity.t()) :: :ok | {:error, term()}
  def withdraw_claim(%Node{} = subject_node, claim_id, %AgentIdentity{} = claimant)
      when is_integer(claim_id) and claim_id > 0 do
    Repo.transaction(fn ->
      claim =
        NodeLineageClaim
        |> where([claim], claim.id == ^claim_id and claim.subject_node_id == ^subject_node.id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      cond do
        is_nil(claim) ->
          Repo.rollback(:claim_not_found)

        claim.claimant_agent_id != claimant.id ->
          Repo.rollback(:claim_not_owned)

        not is_nil(claim.withdrawn_at) ->
          :ok

        true ->
          claim
          |> Changeset.change(withdrawn_at: DateTime.utc_now())
          |> Repo.update!()

          :ok
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec create_or_replace_author_link(Node.t(), AgentIdentity.t(), map()) ::
          {:ok, NodeCrossChainLink.t()} | {:error, term()}
  def create_or_replace_author_link(%Node{} = node, %AgentIdentity{} = agent, attrs) do
    with :ok <- authorize_node_author(node, agent),
         {:ok, normalized} <- normalize_subject_attrs(attrs),
         {:ok, normalized} <- validate_target_node(normalized) do
      Repo.transaction(fn ->
        current =
          NodeCrossChainLink
          |> where([link], link.node_id == ^node.id and is_nil(link.withdrawn_at))
          |> lock("FOR UPDATE")
          |> Repo.one()

        if current do
          current
          |> Changeset.change(
            withdrawn_at: DateTime.utc_now(),
            withdrawn_reason: "replaced"
          )
          |> Repo.update!()
        end

        %NodeCrossChainLink{}
        |> NodeCrossChainLink.changeset(
          Map.merge(normalized, %{
            node_id: node.id,
            author_agent_id: agent.id
          })
        )
        |> Repo.insert!()
      end)
      |> case do
        {:ok, link} -> {:ok, Repo.preload(link, [:author_agent, :target_node])}
        {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec clear_author_link(Node.t(), AgentIdentity.t()) :: :ok | {:error, term()}
  def clear_author_link(%Node{} = node, %AgentIdentity{} = agent) do
    with :ok <- authorize_node_author(node, agent) do
      Repo.transaction(fn ->
        current =
          NodeCrossChainLink
          |> where([link], link.node_id == ^node.id and is_nil(link.withdrawn_at))
          |> lock("FOR UPDATE")
          |> Repo.one()

        case current do
          nil ->
            :ok

          link ->
            link
            |> Changeset.change(withdrawn_at: DateTime.utc_now(), withdrawn_reason: "cleared")
            |> Repo.update!()

            :ok
        end
      end)
      |> case do
        {:ok, :ok} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec create_initial_author_link(Ecto.Repo.t(), Node.t(), AgentIdentity.t(), map() | nil) ::
          {:ok, NodeCrossChainLink.t() | nil} | {:error, term()}
  def create_initial_author_link(_repo, _node, _agent, nil), do: {:ok, nil}

  def create_initial_author_link(repo, %Node{} = node, %AgentIdentity{} = agent, attrs)
      when is_map(attrs) do
    with :ok <- authorize_node_author(node, agent),
         {:ok, normalized} <- normalize_subject_attrs(attrs),
         {:ok, normalized} <- validate_target_node_with_repo(repo, normalized) do
      %NodeCrossChainLink{}
      |> NodeCrossChainLink.changeset(
        Map.merge(normalized, %{
          node_id: node.id,
          author_agent_id: agent.id
        })
      )
      |> repo.insert()
    end
  end

  def create_initial_author_link(_repo, _node, _agent, _attrs),
    do: {:error, :invalid_cross_chain_link}

  @spec encode_link(NodeCrossChainLink.t()) :: map()
  def encode_link(%NodeCrossChainLink{} = link) do
    %{
      id: link.id,
      node_id: link.node_id,
      author_agent_id: link.author_agent_id,
      author_label: maybe_agent_label(link.author_agent),
      relation: link.relation,
      target_chain_id: link.target_chain_id,
      target_chain_label: Chains.label(link.target_chain_id),
      target_node_ref: link.target_node_ref,
      target_node_id: link.target_node_id,
      target_node_title: maybe_node_title(link.target_node),
      target_label: target_label(link.target_chain_id, link.target_node_ref, link.target_node),
      note: link.note,
      withdrawn_at: link.withdrawn_at,
      withdrawn_reason: link.withdrawn_reason,
      inserted_at: link.inserted_at,
      updated_at: link.updated_at
    }
  end

  @spec encode_claim_history(NodeLineageClaim.t()) :: map()
  def encode_claim_history(%NodeLineageClaim{} = claim) do
    %{
      id: claim.id,
      subject_node_id: claim.subject_node_id,
      claimant_agent_id: claim.claimant_agent_id,
      claimant_label: maybe_agent_label(claim.claimant_agent),
      relation: claim.relation,
      target_chain_id: claim.target_chain_id,
      target_chain_label: Chains.label(claim.target_chain_id),
      target_node_ref: claim.target_node_ref,
      target_node_id: claim.target_node_id,
      target_node_title: maybe_node_title(claim.target_node),
      target_label: target_label(claim.target_chain_id, claim.target_node_ref, claim.target_node),
      note: claim.note,
      withdrawn_at: claim.withdrawn_at,
      inserted_at: claim.inserted_at,
      updated_at: claim.updated_at
    }
  end

  defp active_author_link(node_id) do
    NodeCrossChainLink
    |> where([link], link.node_id == ^node_id and is_nil(link.withdrawn_at))
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      link -> Repo.preload(link, [:author_agent, :target_node])
    end
  end

  defp active_claims(node_id) do
    NodeLineageClaim
    |> where([claim], claim.subject_node_id == ^node_id and is_nil(claim.withdrawn_at))
    |> order_by([claim], desc: claim.inserted_at, desc: claim.id)
    |> Repo.all()
    |> preload_claim_assocs()
  end

  defp preload_link_assocs([]), do: []
  defp preload_link_assocs(links), do: Repo.preload(links, [:author_agent, :target_node])

  defp preload_claim_assocs([]), do: []
  defp preload_claim_assocs(claims), do: Repo.preload(claims, [:claimant_agent, :target_node])

  defp maybe_preload_claim({:ok, %NodeLineageClaim{} = claim}),
    do: {:ok, Repo.preload(claim, [:claimant_agent, :target_node])}

  defp maybe_preload_claim(other), do: other

  defp authorize_node_author(%Node{creator_agent_id: creator_agent_id}, %AgentIdentity{
         id: agent_id
       })
       when creator_agent_id == agent_id,
       do: :ok

  defp authorize_node_author(_node, _agent), do: {:error, :not_node_author}

  defp normalize_subject_attrs(attrs) when is_map(attrs) do
    normalized =
      attrs
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> then(fn params ->
        %{
          relation: normalize_relation(Map.get(params, "relation")),
          target_chain_id: normalize_chain_id(Map.get(params, "target_chain_id")),
          target_node_ref: normalize_optional_text(Map.get(params, "target_node_ref")),
          target_node_id: normalize_optional_id(Map.get(params, "target_node_id")),
          note: normalize_optional_text(Map.get(params, "note"))
        }
      end)

    with {:ok, relation} <- fetch_present(normalized.relation, :relation),
         {:ok, target_chain_id} <- fetch_present(normalized.target_chain_id, :target_chain_id),
         {:ok, target_node_ref} <- fetch_present(normalized.target_node_ref, :target_node_ref),
         :ok <- validate_relation(relation),
         :ok <- validate_supported_chain(target_chain_id) do
      {:ok,
       %{
         relation: relation,
         target_chain_id: target_chain_id,
         target_node_ref: target_node_ref,
         target_node_id: normalized.target_node_id,
         note: normalized.note
       }}
    end
  end

  defp normalize_subject_attrs(_attrs), do: {:error, :invalid_payload}

  defp validate_target_node(attrs), do: validate_target_node_with_repo(Repo, attrs)

  defp validate_target_node_with_repo(_repo, %{target_node_id: nil} = attrs), do: {:ok, attrs}

  defp validate_target_node_with_repo(
         repo,
         %{target_node_id: target_node_id, target_chain_id: target_chain_id} = attrs
       ) do
    case repo.get(Node, target_node_id) do
      nil ->
        {:error, :target_node_not_found}

      %Node{chain_id: nil} ->
        {:error, :target_node_chain_unavailable}

      %Node{chain_id: ^target_chain_id} ->
        {:ok, attrs}

      %Node{} ->
        {:error, :target_chain_mismatch}
    end
  end

  defp fetch_present(nil, field), do: {:error, {:required, field}}
  defp fetch_present(value, _field), do: {:ok, value}

  defp validate_relation(relation) do
    if relation in NodeCrossChainLink.relations(), do: :ok, else: {:error, :invalid_relation}
  end

  defp validate_supported_chain(chain_id) do
    if Chains.supported_chain_id?(chain_id), do: :ok, else: {:error, :invalid_target_chain_id}
  end

  defp normalize_relation(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      relation -> relation
    end
  end

  defp normalize_relation(_value), do: nil

  defp normalize_chain_id(value) when is_integer(value) and value > 0, do: value

  defp normalize_chain_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp normalize_chain_id(_value), do: nil

  defp normalize_optional_id(value) when is_integer(value) and value > 0, do: value

  defp normalize_optional_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp normalize_optional_id(_value), do: nil

  defp normalize_optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_text(_value), do: nil

  defp encode_author_link(%NodeCrossChainLink{} = link, mutually_linked?, disputed?) do
    %{
      id: link.id,
      relation: link.relation,
      note: link.note,
      claimant_agent_id: link.author_agent_id,
      claimant_label: maybe_agent_label(link.author_agent),
      declared_by_author: true,
      mutual: mutually_linked?,
      disputed: disputed?,
      target_chain_id: link.target_chain_id,
      target_chain_label: Chains.label(link.target_chain_id),
      target_node_ref: link.target_node_ref,
      target_node_id: link.target_node_id,
      target_node_title: maybe_node_title(link.target_node),
      target_label: target_label(link.target_chain_id, link.target_node_ref, link.target_node),
      inserted_at: link.inserted_at
    }
  end

  defp encode_claim(%NodeLineageClaim{} = claim, author_link, active_claims) do
    disputed? =
      claim_conflicts_with_author?(claim, author_link) or conflicting_claim?(claim, active_claims)

    %{
      id: claim.id,
      relation: claim.relation,
      note: claim.note,
      claimant_agent_id: claim.claimant_agent_id,
      claimant_label: maybe_agent_label(claim.claimant_agent),
      declared_by_author: false,
      mutual: false,
      disputed: disputed?,
      target_chain_id: claim.target_chain_id,
      target_chain_label: Chains.label(claim.target_chain_id),
      target_node_ref: claim.target_node_ref,
      target_node_id: claim.target_node_id,
      target_node_title: maybe_node_title(claim.target_node),
      target_label: target_label(claim.target_chain_id, claim.target_node_ref, claim.target_node),
      inserted_at: claim.inserted_at
    }
  end

  defp projection_status(nil, [], _author_claim), do: "unlinked"

  defp projection_status(_author_link, claims, %{mutual: true}) when claims == [],
    do: "mutually_linked"

  defp projection_status(_author_link, _claims, %{mutual: true, disputed: true}), do: "disputed"
  defp projection_status(_author_link, _claims, %{disputed: true}), do: "disputed"

  defp projection_status(nil, claims, _author_claim) when claims != [],
    do: "externally_claimed_copy"

  defp projection_status(_author_link, _claims, _author_claim), do: "author_claimed"

  defp mutually_linked?(%Node{} = node, %NodeCrossChainLink{target_node_id: target_node_id})
       when is_integer(target_node_id) do
    NodeCrossChainLink
    |> where([link], link.node_id == ^target_node_id and is_nil(link.withdrawn_at))
    |> where([link], link.target_node_id == ^node.id)
    |> Repo.exists?()
  end

  defp mutually_linked?(_node, _link), do: false

  defp disputed?(nil, claims), do: claims != []

  defp disputed?(%NodeCrossChainLink{} = link, claims) do
    Enum.any?(claims, &claim_conflicts_with_author?(&1, link)) or
      multiple_distinct_claim_targets?(claims)
  end

  defp claim_conflicts_with_author?(_claim, nil), do: false

  defp claim_conflicts_with_author?(
         %NodeLineageClaim{} = claim,
         %NodeCrossChainLink{} = author_link
       ) do
    claim.relation != author_link.relation or
      claim.target_chain_id != author_link.target_chain_id or
      claim.target_node_ref != author_link.target_node_ref
  end

  defp multiple_distinct_claim_targets?([]), do: false

  defp multiple_distinct_claim_targets?(claims) do
    claims
    |> Enum.map(&{&1.relation, &1.target_chain_id, &1.target_node_ref})
    |> Enum.uniq()
    |> length() > 1
  end

  defp conflicting_claim?(claim, active_claims) do
    Enum.any?(active_claims, fn other ->
      other.id != claim.id and
        {other.relation, other.target_chain_id, other.target_node_ref} !=
          {claim.relation, claim.target_chain_id, claim.target_node_ref}
    end)
  end

  defp maybe_agent_label(%AgentIdentity{label: label}) when is_binary(label) and label != "",
    do: label

  defp maybe_agent_label(_agent), do: nil

  defp maybe_node_title(%Node{title: title}) when is_binary(title) and title != "", do: title
  defp maybe_node_title(_node), do: nil

  defp target_label(target_chain_id, _target_node_ref, %Node{} = target_node) do
    chain_label = Chains.label(target_chain_id) || "Chain #{target_chain_id}"
    node_label = maybe_node_title(target_node) || "Node #{target_node.id}"
    "#{chain_label} · #{node_label}"
  end

  defp target_label(target_chain_id, target_node_ref, _target_node)
       when is_binary(target_node_ref) do
    chain_label = Chains.label(target_chain_id) || "Chain #{target_chain_id}"
    "#{chain_label} · #{target_node_ref}"
  end

  defp target_label(target_chain_id, _target_node_ref, _target_node),
    do: Chains.label(target_chain_id) || "Chain #{target_chain_id}"
end
