defmodule TechTree.NodesPublishPipelineTest do
  use TechTree.DataCase, async: false

  import Ecto.Query

  alias Oban.Job
  alias TechTree.Agents
  alias TechTree.IPFS.LighthouseClient
  alias TechTree.Nodes
  alias TechTree.Nodes.Node
  alias TechTree.Repo
  alias TechTree.Workers.{AnchorNodeWorker, AwaitNodeReceiptWorker, PinNodeWorker}

  describe "create_agent_node/2 publish cutover" do
    test "persists queued nodes and seeds publish attempt + pin job before side effects" do
      creator = create_agent!("publish-cutover")
      parent = create_public_parent!(creator)
      idempotency_key = "publish-cutover:#{System.unique_integer([:positive])}"

      {:ok, node} =
        Nodes.create_agent_node(creator, %{
          "seed" => "ML",
          "kind" => "hypothesis",
          "title" => "publish-cutover-node",
          "parent_id" => parent.id,
          "notebook_source" => "print('publish-cutover')",
          "idempotency_key" => idempotency_key
        })

      assert node.status == :pinned
      refute has_text?(node.manifest_cid)
      refute has_text?(node.manifest_uri)
      refute has_text?(node.manifest_hash)
      refute has_text?(node.notebook_cid)

      persisted = Repo.get!(Node, node.id)
      assert persisted.publish_idempotency_key == idempotency_key
      assert persisted.manifest_cid == node.manifest_cid

      attempt = Nodes.get_publish_attempt(idempotency_key)
      assert attempt.node_id == node.id
      assert attempt.status == "queued"
      assert attempt.attempt_count == 0

      assert count_jobs(PinNodeWorker, node.id) == 1
      assert count_jobs(AnchorNodeWorker, node.id) == 0
    end

    test "idempotency retries return the same published node" do
      creator = create_agent!("publish-idempotent")
      parent = create_public_parent!(creator)
      idempotency_key = "publish-idempotent:#{System.unique_integer([:positive])}"

      attrs = %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "first-title",
        "parent_id" => parent.id,
        "notebook_source" => "print('first')",
        "idempotency_key" => idempotency_key
      }

      {:ok, first} = Nodes.create_agent_node(creator, attrs)
      assert :ok = PinNodeWorker.perform(%Job{args: %{"node_id" => first.id}})
      first = Repo.get!(Node, first.id)

      {:ok, second} =
        Nodes.create_agent_node(
          creator,
          Map.merge(attrs, %{"title" => "second-title", "notebook_source" => "print('second')"})
        )

      assert second.id == first.id
      assert second.manifest_cid == first.manifest_cid

      assert Repo.aggregate(
               from(n in Node, where: n.publish_idempotency_key == ^idempotency_key),
               :count,
               :id
             ) == 1
    end

    test "skill nodes persist notebook source and all required skill fields" do
      creator = create_agent!("publish-skill")
      parent = create_public_parent!(creator)
      idempotency_key = "publish-skill:#{System.unique_integer([:positive])}"

      attrs = %{
        "seed" => "Skills",
        "kind" => "skill",
        "title" => "skill-persist-node",
        "parent_id" => parent.id,
        "notebook_source" => "print('skill notebook source')",
        "skill_slug" => "skill-#{System.unique_integer([:positive])}",
        "skill_version" => "1.0.0",
        "skill_md_body" => "# Skill markdown body",
        "idempotency_key" => idempotency_key
      }

      {:ok, node} = Nodes.create_agent_node(creator, attrs)
      assert :ok = PinNodeWorker.perform(%Job{args: %{"node_id" => node.id}})
      persisted = Repo.get!(Node, node.id)

      assert persisted.kind == :skill
      assert persisted.notebook_source == attrs["notebook_source"]
      assert persisted.skill_slug == attrs["skill_slug"]
      assert persisted.skill_version == attrs["skill_version"]
      assert persisted.skill_md_body == attrs["skill_md_body"]
      assert has_text?(persisted.skill_md_cid)
      assert has_text?(persisted.manifest_uri)
      assert has_text?(persisted.notebook_cid)
    end

    test "pin failure leaves a failed publish attempt record" do
      creator = create_agent!("publish-pin-failure")
      parent = create_public_parent!(creator)
      idempotency_key = "publish-pin-failure:#{System.unique_integer([:positive])}"

      {:ok, node} =
        Nodes.create_agent_node(creator, %{
          "seed" => "ML",
          "kind" => "hypothesis",
          "title" => "pin-failure",
          "parent_id" => parent.id,
          "notebook_source" => "print('pin failure')",
          "idempotency_key" => idempotency_key
        })

      on_exit(fn ->
        Process.delete({LighthouseClient, :upload_fun})
      end)

      Process.put({LighthouseClient, :upload_fun}, failing_upload_fun())

      assert {:error, %KeyError{}} =
               PinNodeWorker.perform(%Job{
                 args: %{"node_id" => node.id}
               })

      failed_node = Repo.get_by!(Node, publish_idempotency_key: idempotency_key)
      assert failed_node.status == :failed_anchor
      refute has_text?(failed_node.manifest_cid)

      attempt = Nodes.get_publish_attempt(idempotency_key)
      assert attempt.node_id == failed_node.id
      assert attempt.status == "pin_failed"
      assert is_binary(attempt.last_error)
    end

    test "full publish pipeline transitions create->pin->anchor->await->anchored" do
      creator = create_agent!("full-pipeline")
      parent = create_public_parent!(creator)
      idempotency_key = "publish-full:#{System.unique_integer([:positive])}"

      {:ok, node} =
        Nodes.create_agent_node(creator, %{
          "seed" => "ML",
          "kind" => "hypothesis",
          "title" => "publish-full-node",
          "parent_id" => parent.id,
          "notebook_source" => "print('publish-full')",
          "idempotency_key" => idempotency_key
        })

      assert :ok = PinNodeWorker.perform(%Job{args: %{"node_id" => node.id}})
      node = Repo.get!(Node, node.id)
      assert node.status == :pinned

      assert :ok =
               AnchorNodeWorker.perform(%Job{
                 args: %{"node_id" => node.id, "idempotency_key" => node.publish_idempotency_key}
               })

      await_args = fetch_job_args!(AwaitNodeReceiptWorker, node.id)
      assert is_binary(await_args["tx_hash"])

      assert :ok = AwaitNodeReceiptWorker.perform(%Job{args: await_args})

      anchored = Repo.get!(Node, node.id)
      assert anchored.status == :anchored
      assert has_text?(anchored.tx_hash)

      receipt = Repo.get_by!(TechTree.Nodes.NodeChainReceipt, node_id: node.id)
      assert receipt.tx_hash == anchored.tx_hash
      assert receipt.chain_id == 84_532

      attempt = Nodes.get_publish_attempt(node.publish_idempotency_key)
      assert attempt.status == "anchored"
      assert attempt.tx_hash == anchored.tx_hash
    end
  end

  describe "anchor lifecycle transitions" do
    test "maxed await receipt transitions pinned node and publish attempt to failed_anchor" do
      creator = create_agent!("await-failed-anchor")

      node =
        create_node!(creator, %{
          status: :pinned,
          manifest_cid: "bafy-await-failed-manifest",
          manifest_uri: "ipfs://await-failed-manifest",
          manifest_hash: "deadbeefawaitfailed",
          notebook_cid: "bafy-await-failed-notebook",
          tx_hash: "0x" <> String.duplicate("a", 57) <> "pending",
          publish_idempotency_key: "node:#{System.unique_integer([:positive])}:await-failed"
        })

      _ =
        Repo.insert_all("node_publish_attempts", [
          %{
            node_id: node.id,
            idempotency_key: node.publish_idempotency_key,
            manifest_uri: node.manifest_uri,
            manifest_hash: node.manifest_hash,
            tx_hash: node.tx_hash,
            status: "awaiting_receipt",
            attempt_count: 1,
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now()
          }
        ])

      args = %{
        "node_id" => node.id,
        "tx_hash" => node.tx_hash,
        "idempotency_key" => node.publish_idempotency_key
      }

      assert {:error, _reason} =
               AwaitNodeReceiptWorker.perform(%Job{args: args, attempt: 100, max_attempts: 100})

      assert Repo.get!(Node, node.id).status == :failed_anchor

      attempt = Nodes.get_publish_attempt(node.publish_idempotency_key)
      assert attempt.status == "failed_anchor"
      assert is_binary(attempt.last_error)
    end

    test "maxed anchor worker does not downgrade already anchored publish attempt" do
      creator = create_agent!("anchor-anchored")

      node =
        create_node!(creator, %{
          status: :anchored,
          manifest_cid: "bafy-anchored-manifest",
          manifest_uri: "ipfs://anchored-manifest",
          manifest_hash: "deadbeefanchored",
          notebook_cid: "bafy-anchored-notebook",
          publish_idempotency_key: "node:#{System.unique_integer([:positive])}:anchored",
          tx_hash: "0x" <> String.duplicate("b", 64),
          chain_id: 84_532,
          contract_address: random_eth_address(),
          block_number: 1
        })

      _ =
        Repo.insert_all("node_publish_attempts", [
          %{
            node_id: node.id,
            idempotency_key: node.publish_idempotency_key,
            manifest_uri: node.manifest_uri,
            manifest_hash: node.manifest_hash,
            tx_hash: node.tx_hash,
            status: "anchored",
            attempt_count: 1,
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now()
          }
        ])

      args = %{
        "node_id" => node.id,
        "idempotency_key" => node.publish_idempotency_key
      }

      assert :ok = AnchorNodeWorker.perform(%Job{args: args, attempt: 20, max_attempts: 20})

      attempt = Nodes.get_publish_attempt(node.publish_idempotency_key)
      assert attempt.status == "anchored"
      assert Repo.get!(Node, node.id).status == :anchored
    end

    test "maxed anchor worker marks pinned node failed_anchor when create_node cannot submit tx" do
      creator = create_agent!("anchor-max-fail")

      node =
        create_node!(creator, %{
          status: :pinned,
          manifest_cid: "bafy-anchor-max-fail-manifest",
          manifest_uri: "ipfs://anchor-max-fail-manifest",
          manifest_hash: "deadbeefanchormaxfail",
          notebook_cid: "bafy-anchor-max-fail-notebook",
          tx_hash: nil,
          publish_idempotency_key: "node:#{System.unique_integer([:positive])}:anchor-max-fail"
        })

      _ =
        Repo.insert_all("node_publish_attempts", [
          %{
            node_id: node.id,
            idempotency_key: node.publish_idempotency_key,
            manifest_uri: node.manifest_uri,
            manifest_hash: node.manifest_hash,
            tx_hash: nil,
            status: "pinned",
            attempt_count: 0,
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now()
          }
        ])

      previous_ethereum_cfg = Application.get_env(:tech_tree, :ethereum)

      on_exit(fn ->
        if is_nil(previous_ethereum_cfg) do
          Application.delete_env(:tech_tree, :ethereum)
        else
          Application.put_env(:tech_tree, :ethereum, previous_ethereum_cfg)
        end
      end)

      Application.put_env(:tech_tree, :ethereum, mode: :rpc)

      assert {:error, {:create_node_failed, {:rpc_config_missing, :rpc_url}}} =
               AnchorNodeWorker.perform(%Job{
                 args: %{
                   "node_id" => node.id,
                   "idempotency_key" => node.publish_idempotency_key
                 },
                 attempt: 20,
                 max_attempts: 20
               })

      assert Repo.get!(Node, node.id).status == :failed_anchor

      attempt = Nodes.get_publish_attempt(node.publish_idempotency_key)
      assert attempt.status == "failed_anchor"
      assert is_binary(attempt.last_error)
      assert attempt.attempt_count == 1
    end
  end

  defp create_agent!(label_prefix) do
    unique = System.unique_integer([:positive])

    Agents.upsert_verified_agent!(%{
      "chain_id" => "84532",
      "registry_address" => random_eth_address(),
      "token_id" => Integer.to_string(unique),
      "wallet_address" => random_eth_address(),
      "label" => "#{label_prefix}-#{unique}"
    })
  end

  defp create_public_parent!(creator) do
    unique = System.unique_integer([:positive])

    %Node{}
    |> Ecto.Changeset.change(%{
      path: "n#{unique}",
      depth: 0,
      seed: "ML",
      kind: :hypothesis,
      title: "publish-parent-#{unique}",
      status: :anchored,
      notebook_source: "print('parent')",
      publish_idempotency_key: "publish-parent:#{unique}",
      creator_agent_id: creator.id
    })
    |> Repo.insert!()
  end

  defp create_node!(creator, attrs) do
    unique = System.unique_integer([:positive])

    base_attrs = %{
      path: "n#{unique}",
      depth: 0,
      seed: "ML",
      kind: :hypothesis,
      title: "publish-node-#{unique}",
      status: :pinned,
      notebook_source: "print('node')",
      creator_agent_id: creator.id,
      publish_idempotency_key: "node:#{unique}:default"
    }

    %Node{}
    |> Ecto.Changeset.change(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
  end

  defp count_jobs(worker_module, node_id) do
    worker_name = worker_module |> Module.split() |> Enum.join(".")

    Job
    |> where([j], j.worker == ^worker_name)
    |> where([j], fragment("? ->> 'node_id' = ?", j.args, ^to_string(node_id)))
    |> Repo.aggregate(:count, :id)
  end

  defp fetch_job_args!(worker_module, node_id) do
    worker_name = worker_module |> Module.split() |> Enum.join(".")

    Job
    |> where([j], j.worker == ^worker_name)
    |> where([j], fragment("? ->> 'node_id' = ?", j.args, ^to_string(node_id)))
    |> order_by([j], desc: j.id)
    |> limit(1)
    |> select([j], j.args)
    |> Repo.one!()
  end

  defp has_text?(value) when is_binary(value), do: byte_size(String.trim(value)) > 0
  defp has_text?(_value), do: false

  defp failing_upload_fun do
    fn _filename, _content, _opts ->
      raise KeyError, key: :api_key, term: []
    end
  end

  defp random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end
end
