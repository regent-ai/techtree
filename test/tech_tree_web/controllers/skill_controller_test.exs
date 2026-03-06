defmodule TechTreeWeb.SkillControllerTest do
  use TechTreeWeb.ConnCase, async: true

  alias TechTree.Agents
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  describe "GET /skills/:slug/v/:version/skill.md" do
    test "serves markdown body and honors If-None-Match", %{conn: conn} do
      slug = "skill-#{System.unique_integer([:positive])}"
      version = "1.2.3"
      body = "# skill body"

      _skill =
        create_skill_node!(%{skill_slug: slug, skill_version: version, skill_md_body: body})

      response_conn = get(conn, "/skills/#{slug}/v/#{version}/skill.md")
      assert response(response_conn, 200) == body
      assert [etag] = get_resp_header(response_conn, "etag")

      assert Enum.any?(get_resp_header(response_conn, "content-type"), fn header ->
               String.starts_with?(header, "text/markdown")
             end)

      cached_conn =
        build_conn()
        |> put_req_header("if-none-match", etag)
        |> get("/skills/#{slug}/v/#{version}/skill.md")

      assert response(cached_conn, 304) == ""
    end

    test "returns 404 for missing or malformed versions", %{conn: conn} do
      slug = "missing-#{System.unique_integer([:positive])}"

      assert response(get(conn, "/skills/#{slug}/v/1.0.0/skill.md"), 404) == ""

      existing_slug = "skill-#{System.unique_integer([:positive])}"

      _skill =
        create_skill_node!(%{
          skill_slug: existing_slug,
          skill_version: "1.0.0",
          skill_md_body: "# v1"
        })

      assert response(get(conn, "/skills/#{existing_slug}/v/not-semver/skill.md"), 404) == ""
    end
  end

  describe "GET /skills/:slug/latest/skill.md" do
    test "returns the highest semver, not most recent insertion", %{conn: conn} do
      slug = "latest-#{System.unique_integer([:positive])}"

      _older_higher_semver =
        create_skill_node!(%{
          skill_slug: slug,
          skill_version: "2.0.0",
          skill_md_body: "# two"
        })

      _newer_lower_semver =
        create_skill_node!(%{
          skill_slug: slug,
          skill_version: "1.9.9",
          skill_md_body: "# one-nine-nine"
        })

      latest_conn = get(conn, "/skills/#{slug}/latest/skill.md")

      assert response(latest_conn, 200) == "# two"
    end

    test "returns 404 when slug does not exist", %{conn: conn} do
      slug = "missing-latest-#{System.unique_integer([:positive])}"
      assert response(get(conn, "/skills/#{slug}/latest/skill.md"), 404) == ""
    end
  end

  defp create_skill_node!(attrs) do
    unique = System.unique_integer([:positive])
    creator = create_agent!("skill-controller")

    base_attrs = %{
      path: "n#{unique}",
      depth: 0,
      seed: "Skills",
      kind: :skill,
      title: "skill-node-#{unique}",
      status: :anchored,
      notebook_source: "print('skill')",
      publish_idempotency_key: "skill-node:#{unique}",
      creator_agent_id: creator.id,
      skill_slug: "slug-#{unique}",
      skill_version: "1.0.0",
      skill_md_body: "# default skill"
    }

    %Node{}
    |> Ecto.Changeset.change(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
  end

  defp create_agent!(label_prefix) do
    unique = System.unique_integer([:positive])

    Agents.upsert_verified_agent!(%{
      "chain_id" => "8453",
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
