defmodule TechTree.CommentsPhase2Test do
  use TechTree.DataCase, async: true

  alias TechTree.Agents
  alias TechTree.Comments
  alias TechTree.Comments.Comment
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  test "create_agent_comment returns comments_locked when node is locked" do
    creator = create_agent("creator")
    commenter = create_agent("commenter")

    locked_node = create_node!(creator, comments_locked: true)

    assert {:error, :comments_locked} =
             Comments.create_agent_comment(commenter, locked_node.id, %{
               "body_markdown" => "attempted comment",
               "body_plaintext" => "attempted comment"
             })
  end

  test "create_agent_comment writes canonical ready comment" do
    creator = create_agent("creator-ready")
    commenter = create_agent("commenter-ready")

    node = create_node!(creator, comments_locked: false)

    assert {:ok, created} =
             Comments.create_agent_comment(commenter, node.id, %{
               "body_markdown" => "canonical",
               "body_plaintext" => "canonical"
             })

    persisted = Repo.get!(Comment, created.id)

    assert persisted.status == :ready
  end

  defp create_agent(label_prefix) do
    unique = System.unique_integer([:positive])

    Agents.upsert_verified_agent!(%{
      "chain_id" => "11155111",
      "registry_address" => "0x#{label_prefix}registry#{unique}",
      "token_id" => Integer.to_string(unique),
      "wallet_address" => "0x#{label_prefix}wallet#{unique}",
      "label" => "#{label_prefix}-#{unique}"
    })
  end

  defp create_node!(creator, opts) do
    unique = System.unique_integer([:positive])

    attrs = %{
      path: "n#{unique}",
      depth: 0,
      seed: "ML",
      kind: :hypothesis,
      title: "locked-node-#{unique}",
      notebook_source: "print('node')",
      status: :anchored,
      comments_locked: Keyword.get(opts, :comments_locked, false),
      creator_agent_id: creator.id,
      publish_idempotency_key: "node:#{unique}:default"
    }

    %Node{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
  end
end
