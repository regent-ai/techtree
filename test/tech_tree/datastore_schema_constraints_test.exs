defmodule TechTree.DatastoreSchemaConstraintsTest do
  use TechTree.DataCase, async: true

  alias TechTree.Agents
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Comments.Comment
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  describe "Node.creation_changeset/3" do
    test "rejects blank notebook_source" do
      creator = create_agent!()
      parent = create_root_node!(creator)

      changeset =
        %Node{}
        |> Node.creation_changeset(creator, %{
          parent_id: parent.id,
          seed: "ML",
          kind: :hypothesis,
          title: "node-with-blank-notebook",
          notebook_source: "   "
        })
        |> with_materialized_identity(parent)

      refute changeset.valid?
      assert "must be present" in errors_on(changeset).notebook_source
    end

    test "rejects skill nodes missing skill fields" do
      creator = create_agent!()
      parent = create_root_node!(creator)

      changeset =
        %Node{}
        |> Node.creation_changeset(creator, %{
          parent_id: parent.id,
          seed: "ML",
          kind: :skill,
          title: "invalid-skill-node",
          notebook_source: "print('skill')",
          skill_slug: nil,
          skill_version: "1.0.0",
          skill_md_body: "# skill"
        })
        |> with_materialized_identity(parent)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).skill_slug
    end

    test "rejects non-skill nodes carrying skill payload fields" do
      creator = create_agent!()
      parent = create_root_node!(creator)

      changeset =
        %Node{}
        |> Node.creation_changeset(creator, %{
          parent_id: parent.id,
          seed: "ML",
          kind: :hypothesis,
          title: "invalid-non-skill",
          notebook_source: "print('non-skill')",
          skill_slug: "bad-skill",
          skill_version: "1.0.0",
          skill_md_body: "# should not be present"
        })
        |> with_materialized_identity(parent)

      refute changeset.valid?
      errors = errors_on(changeset)
      assert "must be nil unless kind is skill" in errors.skill_slug
      assert "must be nil unless kind is skill" in errors.skill_version
      assert "must be nil unless kind is skill" in errors.skill_md_body
    end

    test "maps parent_id foreign key violations" do
      creator = create_agent!()

      changeset =
        %Node{}
        |> Node.creation_changeset(creator, %{
          parent_id: -1,
          seed: "ML",
          kind: :hypothesis,
          title: "node-invalid-parent",
          notebook_source: "print('fk')"
        })
        |> Ecto.Changeset.put_change(:path, "n#{System.unique_integer([:positive])}")
        |> Ecto.Changeset.put_change(:depth, 1)
        |> Ecto.Changeset.put_change(
          :publish_idempotency_key,
          "node:fk:#{System.unique_integer([:positive])}"
        )

      assert {:error, invalid} = Repo.insert(changeset)
      assert "does not exist" in errors_on(invalid).parent_id
    end

    test "maps duplicate skill slug/version violations" do
      creator = create_agent!()
      parent = create_root_node!(creator)

      existing =
        %Node{}
        |> Node.creation_changeset(creator, %{
          parent_id: parent.id,
          seed: "ML",
          kind: :skill,
          title: "skill-one",
          notebook_source: "print('skill one')",
          skill_slug: "duplicate-skill",
          skill_version: "1.0.0",
          skill_md_body: "# one"
        })
        |> with_materialized_identity(parent)

      assert {:ok, _} = Repo.insert(existing)

      duplicate =
        %Node{}
        |> Node.creation_changeset(creator, %{
          parent_id: parent.id,
          seed: "ML",
          kind: :skill,
          title: "skill-two",
          notebook_source: "print('skill two')",
          skill_slug: "duplicate-skill",
          skill_version: "1.0.0",
          skill_md_body: "# two"
        })
        |> with_materialized_identity(parent)

      assert {:error, invalid} = Repo.insert(duplicate)
      assert "has already been taken" in errors_on(invalid).skill_slug
    end
  end

  describe "Comment.creation_changeset/4" do
    test "requires non-empty markdown body" do
      creator = create_agent!()
      commenter = create_agent!()
      node = create_root_node!(creator)

      changeset =
        Comment.creation_changeset(%Comment{}, commenter, node.id, %{
          "body_markdown" => "",
          "body_plaintext" => ""
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).body_markdown
    end

    test "maps node foreign key violations" do
      commenter = create_agent!()

      changeset =
        Comment.creation_changeset(%Comment{}, commenter, -1, %{
          "body_markdown" => "hello",
          "body_plaintext" => "hello"
        })

      assert {:error, invalid} = Repo.insert(changeset)
      assert "does not exist" in errors_on(invalid).node_id
    end

    test "enforces idempotency uniqueness per author and node" do
      creator = create_agent!()
      commenter = create_agent!()
      node = create_root_node!(creator)

      first =
        Comment.creation_changeset(%Comment{}, commenter, node.id, %{
          "idempotency_key" => "same-key",
          "body_markdown" => "hello one",
          "body_plaintext" => "hello one"
        })

      assert {:ok, _} = Repo.insert(first)

      duplicate =
        Comment.creation_changeset(%Comment{}, commenter, node.id, %{
          "idempotency_key" => "same-key",
          "body_markdown" => "hello two",
          "body_plaintext" => "hello two"
        })

      assert {:error, invalid} = Repo.insert(duplicate)
      assert "has already been taken" in errors_on(invalid).author_agent_id
    end

    test "allows reusing idempotency key across different nodes" do
      creator = create_agent!()
      commenter = create_agent!()
      node_a = create_root_node!(creator)
      node_b = create_root_node!(creator)

      first =
        Comment.creation_changeset(%Comment{}, commenter, node_a.id, %{
          "idempotency_key" => "cross-node-key",
          "body_markdown" => "node-a",
          "body_plaintext" => "node-a"
        })

      second =
        Comment.creation_changeset(%Comment{}, commenter, node_b.id, %{
          "idempotency_key" => "cross-node-key",
          "body_markdown" => "node-b",
          "body_plaintext" => "node-b"
        })

      assert {:ok, _} = Repo.insert(first)
      assert {:ok, _} = Repo.insert(second)
    end
  end

  describe "AgentIdentity.upsert_changeset/2 + Agents.upsert_verified_agent!/1" do
    test "rejects non-positive chain_id" do
      changeset =
        AgentIdentity.upsert_changeset(%AgentIdentity{}, %{
          chain_id: 0,
          registry_address: "0xregistry",
          token_id: Decimal.new(1),
          wallet_address: "0xwallet"
        })

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).chain_id
    end

    test "maps unique chain+registry+token conflicts" do
      attrs = %{
        chain_id: 8453,
        registry_address: "0xregistry-dup",
        token_id: Decimal.new(42),
        wallet_address: "0xwallet-dup-a"
      }

      assert {:ok, _} =
               %AgentIdentity{}
               |> AgentIdentity.upsert_changeset(attrs)
               |> Repo.insert()

      assert {:error, invalid} =
               %AgentIdentity{}
               |> AgentIdentity.upsert_changeset(Map.put(attrs, :wallet_address, "0xwallet-dup-b"))
               |> Repo.insert()

      assert "has already been taken" in errors_on(invalid).chain_id
    end

    test "upsert_verified_agent! updates existing identity for same unique tuple" do
      unique = System.unique_integer([:positive])
      tuple = unique_agent_tuple(unique)

      first =
        Agents.upsert_verified_agent!(%{
          "chain_id" => Integer.to_string(tuple.chain_id),
          "registry_address" => tuple.registry_address,
          "token_id" => Integer.to_string(unique),
          "wallet_address" => "0xwallet#{unique}a",
          "label" => "agent-#{unique}-a"
        })

      second =
        Agents.upsert_verified_agent!(%{
          "chain_id" => Integer.to_string(tuple.chain_id),
          "registry_address" => tuple.registry_address,
          "token_id" => Integer.to_string(unique),
          "wallet_address" => "0xwallet#{unique}b",
          "label" => "agent-#{unique}-b"
        })

      assert first.id == second.id
      assert second.wallet_address == "0xwallet#{unique}b"
      assert second.label == "agent-#{unique}-b"
    end
  end

  defp create_agent! do
    unique = System.unique_integer([:positive])
    tuple = unique_agent_tuple(unique)

    %AgentIdentity{}
    |> AgentIdentity.upsert_changeset(%{
      chain_id: tuple.chain_id,
      registry_address: tuple.registry_address,
      token_id: Decimal.new(unique),
      wallet_address: "0xwallet#{unique}",
      label: "agent-#{unique}",
      status: "active",
      last_verified_at: DateTime.utc_now()
    })
    |> Repo.insert!()
  end

  defp unique_agent_tuple(unique) do
    %{
      chain_id: 8453,
      registry_address: "0xregistry#{unique}"
    }
  end

  defp create_root_node!(creator) do
    unique = System.unique_integer([:positive])

    %Node{}
    |> Ecto.Changeset.change(%{
      path: "n#{unique}",
      depth: 0,
      seed: "ML",
      kind: :hypothesis,
      title: "root-#{unique}",
      notebook_source: "print('root')",
      status: :anchored,
      creator_agent_id: creator.id,
      publish_idempotency_key: "node:root:#{unique}"
    })
    |> Repo.insert!()
  end

  defp with_materialized_identity(changeset, parent) do
    unique = System.unique_integer([:positive])

    changeset
    |> Ecto.Changeset.put_change(:path, "#{parent.path}.n#{unique}")
    |> Ecto.Changeset.put_change(:depth, parent.depth + 1)
    |> Ecto.Changeset.put_change(:publish_idempotency_key, "node:child:#{unique}")
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
