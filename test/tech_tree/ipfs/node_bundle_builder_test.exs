defmodule TechTree.IPFS.NodeBundleBuilderTest do
  use TechTree.DataCase, async: false

  alias TechTree.Agents
  alias TechTree.IPFS.{LighthouseClient, NodeBundleBuilder}
  alias TechTree.Nodes.Node

  @notebook_cid "bafybeibwzifh6x6s6sa2r5y4d7zjz3mx2mhn7abm2wxyx7szj2z5g2rmcq"
  @skill_cid "bafybeihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku"
  @manifest_cid "bafybeia6q4xixf2j6z4mupg3dty6ew2v5vqd4f3i27p2u5mr55ei6lv5we"

  test "build_and_pin/3 emits spec-compliant manifest for skill nodes" do
    creator = create_agent!("bundle-skill")

    parent =
      %Node{}
      |> Ecto.Changeset.change(%{
        path: "n#{System.unique_integer([:positive])}",
        depth: 0,
        seed: "Skills",
        kind: :hypothesis,
        title: "parent",
        status: :anchored,
        notebook_source: "print('parent')",
        manifest_cid: @manifest_cid,
        publish_idempotency_key: "parent:#{System.unique_integer([:positive])}",
        creator_agent_id: creator.id
      })
      |> Repo.insert!()

    node = %Node{
      id: 99_001,
      seed: "Skills",
      kind: :skill,
      title: "Lint Skill",
      parent_id: parent.id
    }

    {upload_fun, upload_log} = capture_upload_fun()

    assert {:ok, bundle} =
             NodeBundleBuilder.build_and_pin(
               node,
               %{
                 "notebook_source" => "print('skill')",
                 "skill_md_body" => "# Skill body"
               },
               upload_fun: upload_fun
             )

    uploads = Agent.get(upload_log, &Enum.reverse/1)

    {"manifest.json", manifest_json} =
      Enum.find(uploads, fn {name, _} -> name == "manifest.json" end)

    manifest = Jason.decode!(manifest_json)

    assert Map.keys(manifest) |> Enum.sort() ==
             [
               "created_at",
               "kind",
               "node_id",
               "notebook_cid",
               "parent_cid",
               "seed",
               "skill_cid",
               "title",
               "version"
             ]

    assert manifest["version"] == "techtree-node-manifest@1"
    assert manifest["node_id"] == node.id
    assert manifest["seed"] == "Skills"
    assert manifest["kind"] == "skill"
    assert manifest["title"] == "Lint Skill"
    assert manifest["notebook_cid"] == @notebook_cid
    assert manifest["skill_cid"] == @skill_cid
    assert manifest["parent_cid"] == @manifest_cid
    assert {:ok, _dt, 0} = DateTime.from_iso8601(manifest["created_at"])

    assert bundle.notebook_cid == @notebook_cid
    assert bundle.skill_md_cid == @skill_cid
    assert bundle.skill_md_body == "# Skill body"
  end

  test "build_and_pin/3 omits optional fields for non-skill root nodes" do
    node = %Node{
      id: 99_002,
      seed: "ML",
      kind: :hypothesis,
      title: "Root Hypothesis",
      parent_id: nil
    }

    {upload_fun, upload_log} = capture_upload_fun()

    assert {:ok, bundle} =
             NodeBundleBuilder.build_and_pin(
               node,
               %{"notebook_source" => "print('hypothesis')"},
               upload_fun: upload_fun
             )

    uploads = Agent.get(upload_log, &Enum.reverse/1)
    filenames = Enum.map(uploads, &elem(&1, 0))

    {"manifest.json", manifest_json} =
      Enum.find(uploads, fn {name, _} -> name == "manifest.json" end)

    manifest = Jason.decode!(manifest_json)

    assert Map.keys(manifest) |> Enum.sort() ==
             ["created_at", "kind", "node_id", "notebook_cid", "seed", "title", "version"]

    refute Map.has_key?(manifest, "skill_cid")
    refute Map.has_key?(manifest, "parent_cid")
    refute "skill.md" in filenames

    assert bundle.skill_md_cid == nil
    assert bundle.skill_md_body == nil
  end

  test "build_and_pin/3 returns an error when skill node is missing skill_md_body" do
    node = %Node{id: 99_003, seed: "Skills", kind: :skill, title: "Broken Skill", parent_id: nil}
    {upload_fun, _upload_log} = capture_upload_fun()

    assert {:error, :skill_md_body_required} =
             NodeBundleBuilder.build_and_pin(
               node,
               %{"notebook_source" => "print('broken')"},
               upload_fun: upload_fun
             )
  end

  test "build_and_pin/3 returns an error when upload returns invalid cid" do
    node = %Node{id: 99_004, seed: "ML", kind: :hypothesis, title: "Bad CID Node", parent_id: nil}

    upload_fun = fn _filename, _content, _opts ->
      %LighthouseClient.UploadResult{
        cid: "not-a-cid",
        name: "x",
        size: 1,
        gateway_url: "https://gateway.test/ipfs/not-a-cid",
        raw: %{}
      }
    end

    assert {:error, :invalid_cid} =
             NodeBundleBuilder.build_and_pin(node, %{"notebook_source" => "print('bad cid')"},
               upload_fun: upload_fun
             )
  end

  defp capture_upload_fun do
    {:ok, upload_log} = Agent.start_link(fn -> [] end)

    upload_fun = fn filename, content, _opts ->
      Agent.update(upload_log, &[{filename, content} | &1])

      cid =
        case filename do
          "notebook.py" -> @notebook_cid
          "skill.md" -> @skill_cid
          "manifest.json" -> @manifest_cid
          _ -> "bafybeic6q4xixf2j6z4mupg3dty6ew2v5vqd4f3i27p2u5mr55ei6lv5we"
        end

      %LighthouseClient.UploadResult{
        cid: cid,
        name: filename,
        size: byte_size(content),
        gateway_url: "https://gateway.test/ipfs/#{cid}",
        raw: %{}
      }
    end

    {upload_fun, upload_log}
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

  defp random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end
end
