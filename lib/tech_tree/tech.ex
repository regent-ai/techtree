defmodule TechTree.Tech do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Repo

  alias TechTree.Tech.{
    Leaderboard,
    RewardAllocation,
    RewardEpoch,
    RewardManifest,
    Withdrawal
  }

  @science_lane "science"
  @input_lane "usdc_input"
  @lanes [@science_lane, @input_lane]
  @policy_version "tech-rewards-v0.2"
  @reputation_filter_version "product-agent-reputation-v1"
  @dust_policy %{"strategy" => "rank_order_remainder"}
  @claim_signature "claim(uint64,uint8,uint256,uint256,bytes32,bytes32[])"
  @withdraw_signature "withdraw(uint256,uint256,address,uint256,uint256)"
  @post_root_signature "postAllocationRoot(uint64,uint8,bytes32,uint256,bytes32,uint64)"
  @register_leaderboard_signature "registerLeaderboard((bytes32,uint8,uint16,uint64,uint64,bytes32,string,bool))"
  @zero_address "0x0000000000000000000000000000000000000000"
  @leaderboard_kinds %{
    "bbh" => 0,
    "biomysterybench" => 1,
    "capsules" => 2,
    "hugging_face" => 3,
    "hugging_science" => 4
  }

  @spec status() :: map()
  def status do
    %{
      contracts: contract_config(),
      current_epoch: current_epoch() |> encode_epoch()
    }
  end

  @spec current_epoch() :: RewardEpoch.t() | nil
  def current_epoch do
    RewardEpoch
    |> order_by([epoch], desc: epoch.epoch)
    |> limit(1)
    |> Repo.one()
  end

  @spec list_leaderboards(map()) :: [Leaderboard.t()]
  def list_leaderboards(params \\ %{}) when is_map(params) do
    limit = TechTree.QueryHelpers.parse_limit(params, 50)

    Leaderboard
    |> maybe_filter_leaderboard_status(Map.get(params, "status"))
    |> order_by([leaderboard], desc: leaderboard.active, asc: leaderboard.leaderboard_id)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec list_reward_manifests(map()) :: [RewardManifest.t()]
  def list_reward_manifests(params \\ %{}) when is_map(params) do
    limit = TechTree.QueryHelpers.parse_limit(params, 50)

    RewardManifest
    |> maybe_filter_epoch(Map.get(params, "epoch"))
    |> maybe_filter_lane(Map.get(params, "lane"))
    |> order_by([manifest], desc: manifest.epoch, asc: manifest.lane)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec reward_proof(map()) :: {:ok, map()} | {:error, term()}
  def reward_proof(params) when is_map(params) do
    with {:ok, epoch} <- required_epoch(params),
         {:ok, lane} <- required_lane(params),
         {:ok, agent_id} <- required_agent_id(params),
         %RewardAllocation{} = allocation <- fetch_allocation(epoch, lane, agent_id) do
      {:ok, encode_proof(allocation)}
    else
      nil -> {:error, :reward_proof_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec prepare_reward_claim(AgentIdentity.t(), map()) :: {:ok, map()} | {:error, term()}
  def prepare_reward_claim(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    with {:ok, agent_id} <- ensure_agent_id(agent, Map.get(attrs, "agent_id")),
         {:ok, proof} <- reward_proof(Map.put(attrs, "agent_id", agent_id)) do
      transaction = %{
        chain_id: contract_config().chain_id,
        to: contract_config().reward_router,
        value: "0",
        function_signature: @claim_signature,
        data: nil,
        args: [
          proof.epoch,
          lane_index(proof.lane),
          proof.agent_id,
          proof.amount,
          proof.allocation_ref,
          proof.proof
        ]
      }

      {:ok, %{transaction: transaction, proof: proof}}
    end
  end

  @spec prepare_withdrawal(AgentIdentity.t(), map()) :: {:ok, map()} | {:error, term()}
  def prepare_withdrawal(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    with {:ok, agent_id} <- ensure_agent_id(agent, Map.get(attrs, "agent_id")),
         {:ok, amount} <- required_amount(attrs, "amount"),
         {:ok, tech_recipient} <- required_address(attrs, "tech_recipient"),
         {:ok, min_usdc_out} <- required_nonzero_amount(attrs, "min_usdc_out"),
         {:ok, deadline} <- required_positive_integer(attrs, "deadline") do
      transaction = %{
        chain_id: contract_config().chain_id,
        to: contract_config().agent_reward_vault,
        value: "0",
        function_signature: @withdraw_signature,
        data: nil,
        args: [agent_id, amount, tech_recipient, min_usdc_out, deadline]
      }

      attrs = %{
        "withdrawal_id" => generated_id("techw"),
        "agent_identity_id" => agent.id,
        "agent_id" => agent_id,
        "amount" => amount,
        "tech_recipient" => tech_recipient,
        "min_usdc_out" => min_usdc_out,
        "deadline" => deadline,
        "transaction" => atom_to_string_map(transaction)
      }

      %Withdrawal{}
      |> Withdrawal.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, withdrawal} ->
          {:ok, %{transaction: transaction, withdrawal: encode_withdrawal(withdrawal)}}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @spec prepare_leaderboard_registration(AgentIdentity.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def prepare_leaderboard_registration(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    with {:ok, leaderboard_attrs} <- leaderboard_attrs(agent, attrs) do
      leaderboard_changeset = Leaderboard.changeset(%Leaderboard{}, leaderboard_attrs)

      Multi.new()
      |> Multi.insert(:leaderboard, leaderboard_changeset)
      |> Repo.transaction()
      |> case do
        {:ok, %{leaderboard: leaderboard}} ->
          transaction = %{
            chain_id: contract_config().chain_id,
            to: contract_config().leaderboard_registry,
            value: "0",
            function_signature: @register_leaderboard_signature,
            data: nil,
            args: [
              [
                leaderboard_id_bytes32(leaderboard.leaderboard_id),
                leaderboard_kind_index(leaderboard.kind),
                leaderboard.weight_bps,
                leaderboard.starts_epoch || 0,
                leaderboard.ends_epoch || 0,
                leaderboard.config_hash,
                leaderboard.uri,
                leaderboard.active
              ]
            ]
          }

          {:ok, %{transaction: transaction, leaderboard: encode_leaderboard(leaderboard)}}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  @spec prepare_reward_root(AgentIdentity.t(), map()) :: {:ok, map()} | {:error, term()}
  def prepare_reward_root(%AgentIdentity{}, attrs) when is_map(attrs) do
    with {:ok, epoch} <- required_epoch(attrs),
         {:ok, lane} <- required_lane(attrs),
         {:ok, total_budget_amount} <- required_nonzero_amount(attrs, "total_budget_amount"),
         {:ok, allocations} <- required_allocations(attrs),
         {:ok, prepared} <- build_manifest(epoch, lane, total_budget_amount, attrs, allocations) do
      insert_manifest(prepared)
    end
  end

  @spec encode_status(map()) :: map()
  def encode_status(status), do: status

  @spec encode_epoch(RewardEpoch.t() | nil) :: map() | nil
  def encode_epoch(nil), do: nil

  def encode_epoch(%RewardEpoch{} = epoch) do
    %{
      epoch: epoch.epoch,
      status: epoch.status,
      starts_at: epoch.starts_at,
      ends_at: epoch.ends_at,
      total_emission_amount: epoch.total_emission_amount,
      science_budget_amount: epoch.science_budget_amount,
      input_budget_amount: epoch.input_budget_amount
    }
  end

  @spec encode_leaderboard(Leaderboard.t()) :: map()
  def encode_leaderboard(%Leaderboard{} = leaderboard) do
    %{
      leaderboard_id: leaderboard.leaderboard_id,
      kind: leaderboard.kind,
      title: leaderboard.title,
      weight_bps: leaderboard.weight_bps,
      starts_epoch: leaderboard.starts_epoch,
      ends_epoch: leaderboard.ends_epoch,
      config_hash: leaderboard.config_hash,
      uri: leaderboard.uri,
      active: leaderboard.active
    }
  end

  @spec encode_manifest(RewardManifest.t()) :: map()
  def encode_manifest(%RewardManifest{} = manifest) do
    %{
      manifest_id: manifest.manifest_id,
      epoch: manifest.epoch,
      lane: manifest.lane,
      merkle_root: manifest.merkle_root,
      manifest_hash: manifest.manifest_hash,
      total_allocated_amount: manifest.total_allocated_amount,
      allocation_count: manifest.allocation_count,
      policy_version: manifest.policy_version,
      leaderboard_ids: manifest.leaderboard_ids
    }
  end

  defp insert_manifest(prepared) do
    epoch_attrs = %{
      "epoch" => prepared.epoch,
      "status" => "sealed",
      "total_emission_amount" => prepared.total_allocated_amount,
      "science_budget_amount" => science_budget(prepared),
      "input_budget_amount" => input_budget(prepared)
    }

    manifest_attrs = %{
      "manifest_id" => prepared.manifest_id,
      "epoch" => prepared.epoch,
      "lane" => prepared.lane,
      "merkle_root" => prepared.merkle_root,
      "manifest_hash" => prepared.manifest_hash,
      "total_allocated_amount" => prepared.total_allocated_amount,
      "allocation_count" => length(prepared.allocations),
      "policy_version" => @policy_version,
      "leaderboard_ids" => prepared.leaderboard_ids,
      "reputation_filter_version" => @reputation_filter_version,
      "dust_policy" => @dust_policy,
      "challenge_ends_at" => prepared.challenge_ends_at
    }

    multi =
      Multi.new()
      |> Multi.run(:epoch, fn repo, _changes ->
        upsert_epoch_summary(repo, epoch_attrs, prepared)
      end)
      |> Multi.insert(:manifest, RewardManifest.changeset(%RewardManifest{}, manifest_attrs))

    multi =
      Enum.reduce(prepared.allocations, multi, fn allocation, multi ->
        Multi.insert(
          multi,
          {:allocation, allocation.allocation_id},
          RewardAllocation.changeset(%RewardAllocation{}, atom_to_string_map(allocation))
        )
      end)

    Repo.transaction(multi)
    |> case do
      {:ok, %{manifest: manifest}} ->
        transaction = %{
          chain_id: contract_config().chain_id,
          to: contract_config().reward_router,
          value: "0",
          function_signature: @post_root_signature,
          data: nil,
          args: [
            prepared.epoch,
            lane_index(prepared.lane),
            prepared.merkle_root,
            prepared.total_allocated_amount,
            prepared.manifest_hash,
            prepared.challenge_ends_at || 0
          ]
        }

        {:ok, %{transaction: transaction, manifest: encode_manifest(manifest)}}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp build_manifest(epoch, lane, total_budget_amount, attrs, allocation_inputs) do
    total_budget = String.to_integer(total_budget_amount)
    ranked = rank_allocations(allocation_inputs)

    prepared_rows =
      lane
      |> distribute_allocations(total_budget, ranked)
      |> finalize_allocation_rows(epoch, lane)

    leaves = Enum.map(prepared_rows, & &1.leaf)
    {root, proofs} = merkle_tree(leaves)

    allocations =
      prepared_rows
      |> Enum.with_index()
      |> Enum.map(fn {row, index} ->
        %{
          allocation_id: generated_id("techa"),
          manifest_id: nil,
          epoch: epoch,
          lane: lane,
          agent_id: row.agent_id,
          wallet_address: row.wallet_address,
          amount: row.amount,
          allocation_ref: row.allocation_ref,
          proof: Enum.map(Enum.at(proofs, index), &hex/1),
          rank: row.rank,
          score: row.score,
          leaderboard_id: row.leaderboard_id
        }
      end)

    manifest_hash = manifest_hash(epoch, lane, allocations)
    manifest_id = "techm_" <> String.slice(String.replace_prefix(manifest_hash, "0x", ""), 0, 24)
    allocations = Enum.map(allocations, &Map.put(&1, :manifest_id, manifest_id))

    {:ok,
     %{
       manifest_id: manifest_id,
       epoch: epoch,
       lane: lane,
       merkle_root: hex(root),
       manifest_hash: manifest_hash,
       total_allocated_amount: total_budget_amount,
       leaderboard_ids: leaderboard_ids(attrs),
       challenge_ends_at: optional_integer(attrs, "challenge_ends_at"),
       allocations: allocations
     }}
  end

  defp rank_allocations(allocation_inputs) do
    allocation_inputs
    |> Enum.map(fn input ->
      %{
        agent_id: Map.fetch!(input, "agent_id"),
        wallet_address: Map.get(input, "wallet_address"),
        score: Decimal.new(Map.fetch!(input, "score")),
        leaderboard_id: Map.get(input, "leaderboard_id")
      }
    end)
    |> Enum.sort(fn left, right ->
      case Decimal.compare(left.score, right.score) do
        :gt -> true
        :lt -> false
        :eq -> left.agent_id <= right.agent_id
      end
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {row, rank} -> Map.put(row, :rank, rank) end)
  end

  defp distribute_allocations(@input_lane, total_budget, ranked) do
    split_integer(ranked, total_budget)
  end

  defp distribute_allocations(@science_lane, total_budget, ranked) do
    count = length(ranked)
    top_limit = max(ceil_div(count, 5), 1)
    mid_limit = min(50, count)

    top_rows = Enum.filter(ranked, &(&1.rank <= top_limit))
    mid_rows = Enum.filter(ranked, &(&1.rank > top_limit and &1.rank <= mid_limit))
    tail_rows = Enum.filter(ranked, &(&1.rank > mid_limit))

    top_budget = div(total_budget * 7_500, 10_000)
    mid_budget = div(total_budget * 2_000, 10_000)
    tail_budget = total_budget - top_budget - mid_budget

    distribute_buckets([{top_rows, top_budget}, {mid_rows, mid_budget}, {tail_rows, tail_budget}])
  end

  defp distribute_buckets(buckets) do
    {rows, carry} =
      Enum.reduce(buckets, {[], 0}, fn {bucket_rows, budget}, {acc, carry} ->
        if bucket_rows == [] do
          {acc, carry + budget}
        else
          {acc ++ split_integer(bucket_rows, budget + carry), 0}
        end
      end)

    case {rows, carry} do
      {[], _carry} -> []
      {[first | rest], extra} -> [Map.update!(first, :amount_integer, &(&1 + extra)) | rest]
    end
  end

  defp split_integer(rows, budget) do
    count = length(rows)
    share = div(budget, count)
    remainder = rem(budget, count)

    rows
    |> Enum.with_index()
    |> Enum.map(fn {row, index} ->
      Map.put(row, :amount_integer, share + if(index < remainder, do: 1, else: 0))
    end)
  end

  defp finalize_allocation_rows(rows, epoch, lane) do
    Enum.map(rows, fn row ->
      amount = Integer.to_string(row.amount_integer)
      allocation_ref = allocation_ref(row, amount)
      leaf = allocation_leaf(epoch, lane, row, amount, allocation_ref)

      row
      |> Map.put(:amount, amount)
      |> Map.put(:lane, lane)
      |> Map.put(:allocation_ref, allocation_ref)
      |> Map.put(:leaf, leaf)
    end)
  end

  defp allocation_ref(row, amount) do
    keccak_hex(
      Enum.join(
        [
          "tech:v0.2:allocation",
          row.agent_id,
          Integer.to_string(row.rank),
          amount,
          row.leaderboard_id || ""
        ],
        "|"
      )
    )
  end

  defp allocation_leaf(epoch, lane, row, amount, allocation_ref) do
    (encode_uint(epoch) <>
       encode_uint(lane_index(lane)) <>
       encode_uint(String.to_integer(row.agent_id)) <>
       encode_uint(String.to_integer(amount)) <>
       bytes32!(allocation_ref))
    |> keccak()
  end

  defp merkle_tree([leaf]), do: {leaf, [[]]}

  defp merkle_tree(leaves) do
    indexed = Enum.with_index(leaves)
    proofs = Map.new(indexed, fn {_leaf, index} -> {index, []} end)
    build_merkle_level(indexed, proofs)
  end

  defp build_merkle_level([{root, _index}], proofs), do: {root, proof_list(proofs)}

  defp build_merkle_level(level, proofs) do
    {next_level, next_proofs} =
      level
      |> Enum.chunk_every(2)
      |> Enum.reduce({[], proofs}, fn
        [{left, left_index}, {right, right_index}], {next, proof_acc} ->
          parent = hash_pair(left, right)

          proof_acc =
            proof_acc
            |> Map.update!(left_index, &(&1 ++ [right]))
            |> Map.update!(right_index, &(&1 ++ [left]))

          {[{parent, left_index} | next], proof_acc}

        [{left, left_index}], {next, proof_acc} ->
          {[{left, left_index} | next], proof_acc}
      end)

    next_level
    |> Enum.reverse()
    |> build_merkle_level(next_proofs)
  end

  defp proof_list(proofs) do
    proofs
    |> Enum.sort_by(fn {index, _proof} -> index end)
    |> Enum.map(fn {_index, proof} -> proof end)
  end

  defp hash_pair(left, right) when left <= right, do: keccak(left <> right)
  defp hash_pair(left, right), do: keccak(right <> left)

  defp manifest_hash(epoch, lane, allocations) do
    allocations
    |> Enum.sort_by(& &1.rank)
    |> Enum.map_join("\n", fn allocation ->
      Enum.join(
        [
          epoch,
          lane,
          allocation.rank,
          allocation.agent_id,
          allocation.amount,
          allocation.allocation_ref,
          allocation.leaderboard_id || ""
        ],
        "|"
      )
    end)
    |> keccak_hex()
  end

  defp fetch_allocation(epoch, lane, agent_id) do
    RewardAllocation
    |> where([allocation], allocation.epoch == ^epoch)
    |> where([allocation], allocation.lane == ^lane)
    |> where([allocation], allocation.agent_id == ^agent_id)
    |> order_by([allocation], desc: allocation.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp encode_proof(%RewardAllocation{} = allocation) do
    %{
      epoch: allocation.epoch,
      lane: allocation.lane,
      agent_id: allocation.agent_id,
      amount: allocation.amount,
      allocation_ref: allocation.allocation_ref,
      proof: allocation.proof,
      merkle_root: Repo.get!(RewardManifest, allocation.manifest_id).merkle_root
    }
  end

  defp encode_withdrawal(%Withdrawal{} = withdrawal) do
    %{
      withdrawal_id: withdrawal.withdrawal_id,
      agent_id: withdrawal.agent_id,
      amount: withdrawal.amount,
      status: withdrawal.status
    }
  end

  defp leaderboard_attrs(%AgentIdentity{} = agent, attrs) do
    with {:ok, weight_bps} <- required_bps(attrs, "weight_bps"),
         {:ok, config_hash} <- required_bytes32(attrs, "config_hash"),
         {:ok, kind} <- required_leaderboard_kind(attrs),
         {:ok, title} <- required_string(attrs, "title"),
         {:ok, uri} <- required_string(attrs, "uri"),
         {:ok, leaderboard_id} <- required_string(attrs, "leaderboard_id") do
      {:ok,
       %{
         "leaderboard_id" => leaderboard_id,
         "created_by_agent_id" => agent.id,
         "kind" => kind,
         "title" => title,
         "weight_bps" => weight_bps,
         "starts_epoch" => optional_integer(attrs, "starts_epoch"),
         "ends_epoch" => optional_integer(attrs, "ends_epoch"),
         "config_hash" => config_hash,
         "uri" => uri,
         "active" => Map.get(attrs, "active", true)
       }}
    end
  end

  defp required_allocations(attrs) do
    case Map.get(attrs, "allocations") do
      rows when is_list(rows) and rows != [] ->
        if Enum.all?(rows, &valid_allocation_input?/1) do
          {:ok, rows}
        else
          {:error, :invalid_allocation}
        end

      _ ->
        {:error, :allocations_required}
    end
  end

  defp valid_allocation_input?(%{"agent_id" => agent_id, "score" => score}) do
    match?({:ok, _}, required_agent_id(%{"agent_id" => agent_id})) and
      match?({:ok, _}, decimal_string(score))
  end

  defp valid_allocation_input?(_input), do: false

  defp required_epoch(attrs), do: required_non_negative_integer(attrs, "epoch")

  defp required_lane(attrs) do
    case Map.get(attrs, "lane") do
      lane when lane in @lanes -> {:ok, lane}
      _ -> {:error, :invalid_reward_lane}
    end
  end

  defp required_agent_id(attrs), do: required_agent_id(attrs, "agent_id")

  defp required_agent_id(attrs, key) when is_map(attrs) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        normalized = String.trim(value)

        if Regex.match?(~r/^[0-9]+$/, normalized) do
          {:ok, normalized}
        else
          {:error, :invalid_agent_id}
        end

      _ ->
        {:error, :agent_id_required}
    end
  end

  defp ensure_agent_id(%AgentIdentity{} = agent, requested_agent_id) do
    with {:ok, agent_id} <- agent_token_id(agent),
         {:ok, requested} <- required_agent_id(%{"agent_id" => requested_agent_id}) do
      if requested == agent_id do
        {:ok, agent_id}
      else
        {:error, :agent_id_mismatch}
      end
    end
  end

  defp agent_token_id(%AgentIdentity{token_id: %Decimal{} = token_id}) do
    token_id
    |> Decimal.to_string(:normal)
    |> case do
      value when is_binary(value) ->
        if String.contains?(value, ".") do
          {:error, :invalid_agent_id}
        else
          {:ok, value}
        end
    end
  end

  defp agent_token_id(_agent), do: {:error, :invalid_agent_id}

  defp required_string(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, String.to_atom("#{key}_required")}
          trimmed -> {:ok, trimmed}
        end

      _ ->
        {:error, String.to_atom("#{key}_required")}
    end
  end

  defp required_amount(attrs, key) do
    with {:ok, value} <- required_string(attrs, key) do
      if Regex.match?(~r/^[0-9]+$/, value), do: {:ok, value}, else: {:error, :invalid_amount}
    end
  end

  defp required_nonzero_amount(attrs, key) do
    with {:ok, value} <- required_amount(attrs, key) do
      if String.to_integer(value) > 0, do: {:ok, value}, else: {:error, :amount_zero}
    end
  end

  defp required_address(attrs, key) do
    with {:ok, value} <- required_string(attrs, key) do
      if Regex.match?(~r/^0x[0-9a-fA-F]{40}$/, value) do
        {:ok, String.downcase(value)}
      else
        {:error, :invalid_address}
      end
    end
  end

  defp required_bytes32(attrs, key) do
    with {:ok, value} <- required_string(attrs, key) do
      if Regex.match?(~r/^0x[0-9a-fA-F]{64}$/, value) do
        {:ok, String.downcase(value)}
      else
        {:error, :invalid_bytes32}
      end
    end
  end

  defp required_positive_integer(attrs, key) do
    with {:ok, value} <- required_non_negative_integer(attrs, key) do
      if value > 0, do: {:ok, value}, else: {:error, :invalid_integer}
    end
  end

  defp required_non_negative_integer(attrs, key) do
    case Map.get(attrs, key) do
      value when is_integer(value) and value >= 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {parsed, ""} when parsed >= 0 -> {:ok, parsed}
          _ -> {:error, :invalid_integer}
        end

      _ ->
        {:error, String.to_atom("#{key}_required")}
    end
  end

  defp optional_integer(attrs, key) do
    case Map.get(attrs, key) do
      nil -> nil
      "" -> nil
      value when is_integer(value) and value >= 0 -> value
      value when is_binary(value) -> value |> String.trim() |> Integer.parse() |> elem(0)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp required_bps(attrs, key) do
    with {:ok, value} <- required_non_negative_integer(attrs, key) do
      if value <= 10_000, do: {:ok, value}, else: {:error, :invalid_weight_bps}
    end
  end

  defp required_leaderboard_kind(attrs) do
    with {:ok, kind} <- required_string(attrs, "kind") do
      if Map.has_key?(@leaderboard_kinds, kind) do
        {:ok, kind}
      else
        {:error, :invalid_leaderboard_kind}
      end
    end
  end

  defp decimal_string(value) when is_binary(value) do
    case Decimal.parse(String.trim(value)) do
      {decimal, ""} -> {:ok, decimal}
      _ -> {:error, :invalid_score}
    end
  end

  defp decimal_string(_value), do: {:error, :invalid_score}

  defp maybe_filter_leaderboard_status(query, "active"),
    do: where(query, [leaderboard], leaderboard.active == true)

  defp maybe_filter_leaderboard_status(query, "inactive"),
    do: where(query, [leaderboard], leaderboard.active == false)

  defp maybe_filter_leaderboard_status(query, _status), do: query

  defp maybe_filter_epoch(query, nil), do: query

  defp maybe_filter_epoch(query, value) do
    case required_non_negative_integer(%{"epoch" => value}, "epoch") do
      {:ok, epoch} -> where(query, [manifest], manifest.epoch == ^epoch)
      {:error, _reason} -> query
    end
  end

  defp maybe_filter_lane(query, lane) when lane in @lanes,
    do: where(query, [manifest], manifest.lane == ^lane)

  defp maybe_filter_lane(query, _lane), do: query

  defp lane_index(@science_lane), do: 0
  defp lane_index(@input_lane), do: 1

  defp leaderboard_kind_index(kind), do: Map.get(@leaderboard_kinds, kind, 255)

  defp leaderboard_id_bytes32("0x" <> hash = value) when byte_size(hash) == 64, do: value
  defp leaderboard_id_bytes32(id), do: keccak_hex("tech:v0.2:leaderboard:" <> id)

  defp leaderboard_ids(attrs) do
    case Map.get(attrs, "leaderboard_ids") do
      values when is_list(values) -> Enum.filter(values, &is_binary/1)
      _ -> []
    end
  end

  defp science_budget(%{lane: @science_lane, total_allocated_amount: amount}), do: amount
  defp science_budget(_prepared), do: "0"
  defp input_budget(%{lane: @input_lane, total_allocated_amount: amount}), do: amount
  defp input_budget(_prepared), do: "0"

  defp upsert_epoch_summary(repo, epoch_attrs, prepared) do
    case repo.get(RewardEpoch, prepared.epoch) do
      nil ->
        %RewardEpoch{}
        |> RewardEpoch.changeset(epoch_attrs)
        |> repo.insert()

      %RewardEpoch{} = epoch ->
        science_budget =
          if prepared.lane == @science_lane,
            do: prepared.total_allocated_amount,
            else: epoch.science_budget_amount

        input_budget =
          if prepared.lane == @input_lane,
            do: prepared.total_allocated_amount,
            else: epoch.input_budget_amount

        attrs = %{
          "status" => "sealed",
          "science_budget_amount" => science_budget,
          "input_budget_amount" => input_budget,
          "total_emission_amount" => sum_amounts(science_budget, input_budget)
        }

        epoch
        |> RewardEpoch.changeset(attrs)
        |> repo.update()
    end
  end

  defp sum_amounts(left, right),
    do: Integer.to_string(String.to_integer(left) + String.to_integer(right))

  defp contract_config do
    cfg = Application.get_env(:tech_tree, :tech, [])

    %{
      chain_id: cfg |> Keyword.get(:chain_id, 8_453) |> parse_chain_id(),
      token: Keyword.get(cfg, :token_address, @zero_address),
      reward_router: Keyword.get(cfg, :reward_router_address, @zero_address),
      agent_reward_vault: Keyword.get(cfg, :agent_reward_vault_address, @zero_address),
      emission_controller: Keyword.get(cfg, :emission_controller_address, @zero_address),
      leaderboard_registry: Keyword.get(cfg, :leaderboard_registry_address, @zero_address),
      exit_fee_splitter: Keyword.get(cfg, :exit_fee_splitter_address, @zero_address)
    }
  end

  defp parse_chain_id(value) when is_integer(value), do: value

  defp parse_chain_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {chain_id, ""} -> chain_id
      _ -> 8_453
    end
  end

  defp parse_chain_id(_value), do: 8_453

  defp generated_id(prefix),
    do: "#{prefix}_" <> Base.encode16(:crypto.strong_rand_bytes(10), case: :lower)

  defp keccak_hex(value) when is_binary(value), do: value |> keccak() |> hex()
  defp keccak(value) when is_binary(value), do: :jose_jwa_sha3.keccak(1088, 512, value, 1, 32)
  defp hex(binary), do: "0x" <> Base.encode16(binary, case: :lower)

  defp bytes32!("0x" <> hex) when byte_size(hex) == 64, do: Base.decode16!(hex, case: :mixed)
  defp bytes32!(_value), do: raise(ArgumentError, "bytes32 value required")

  defp encode_uint(value) when is_integer(value) and value >= 0 do
    <<value::unsigned-big-integer-size(256)>>
  end

  defp ceil_div(0, _divisor), do: 0
  defp ceil_div(value, divisor), do: div(value + divisor - 1, divisor)

  defp atom_to_string_map(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end
end
