defmodule TechTreeWeb.AgentCommentControllerTest do
  use TechTreeWeb.ConnCase, async: false

  alias TechTree.Agents
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  test "requires SIWA auth", %{conn: conn} do
    response =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/v1/tree/comments", %{})
      |> json_response(401)

    assert %{"error" => %{"code" => "agent_auth_required"}} = response
  end

  test "returns 422 when node_id is invalid", %{conn: conn} do
    headers = create_agent_headers!("comment-invalid-node")

    response =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/tree/comments", %{
        "node_id" => "bad-id",
        "body_markdown" => "invalid",
        "body_plaintext" => "invalid"
      })
      |> json_response(422)

    assert %{"error" => %{"code" => "invalid_node_id"}} = response
  end

  test "returns 404 when target node does not exist", %{conn: conn} do
    headers = create_agent_headers!("comment-node-missing")

    response =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/tree/comments", %{
        "node_id" => 9_999_999,
        "body_markdown" => "missing node",
        "body_plaintext" => "missing node"
      })
      |> json_response(404)

    assert %{"error" => %{"code" => "node_not_found"}} = response
  end

  test "creates comment and idempotent retries return the same comment", %{conn: conn} do
    headers = create_agent_headers!("comment-idempotent")
    node = create_node!(headers.agent, comments_locked: false)
    idempotency_key = "comment:#{System.unique_integer([:positive])}"

    first_response =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/tree/comments", %{
        "node_id" => node.id,
        "body_markdown" => "first body",
        "body_plaintext" => "first body",
        "idempotency_key" => idempotency_key
      })
      |> json_response(201)

    assert %{"data" => %{"comment_id" => comment_id, "node_id" => node_id}} = first_response
    assert node_id == node.id

    second_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(headers)
      |> post("/v1/tree/comments", %{
        "node_id" => node.id,
        "body_markdown" => "second body",
        "body_plaintext" => "second body",
        "idempotency_key" => idempotency_key
      })
      |> json_response(201)

    assert %{"data" => %{"comment_id" => ^comment_id, "node_id" => ^node_id}} = second_response
  end

  test "returns 403 when comments are locked", %{conn: conn} do
    headers = create_agent_headers!("comment-locked")
    node = create_node!(headers.agent, comments_locked: true)

    response =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/tree/comments", %{
        "node_id" => node.id,
        "body_markdown" => "nope",
        "body_plaintext" => "nope"
      })
      |> json_response(403)

    assert %{"error" => %{"code" => "comments_locked"}} = response
  end

  test "allows comments on creator-owned pinned nodes", %{conn: conn} do
    headers = create_agent_headers!("comment-owned-pinned")
    node = create_node!(headers.agent, comments_locked: false, status: :pinned)

    response =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/tree/comments", %{
        "node_id" => node.id,
        "body_markdown" => "owned pinned",
        "body_plaintext" => "owned pinned"
      })
      |> json_response(201)

    assert %{"data" => %{"node_id" => node_id}} = response
    assert node_id == node.id
  end

  test "returns 404 for hidden nodes", %{conn: conn} do
    headers = create_agent_headers!("comment-hidden")
    node = create_node!(headers.agent, comments_locked: false, status: :hidden)

    response =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/tree/comments", %{
        "node_id" => node.id,
        "body_markdown" => "hidden nope",
        "body_plaintext" => "hidden nope"
      })
      |> json_response(404)

    assert %{"error" => %{"code" => "node_not_found"}} = response
  end

  test "returns 404 for nodes created by banned agents", %{conn: conn} do
    headers = create_agent_headers!("comment-visible")
    banned_creator = create_agent_headers!("comment-banned", status: "banned")
    node = create_node!(banned_creator.agent, comments_locked: false)

    response =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/tree/comments", %{
        "node_id" => node.id,
        "body_markdown" => "banned nope",
        "body_plaintext" => "banned nope"
      })
      |> json_response(404)

    assert %{"error" => %{"code" => "node_not_found"}} = response
  end

  test "rate limits repeated non-idempotent comments on the same node", %{conn: conn} do
    headers = create_agent_headers!("comment-rate-limit")
    node = create_node!(headers.agent, comments_locked: false)

    assert %{"data" => %{"comment_id" => _comment_id, "node_id" => node_id}} =
             conn
             |> with_siwa_headers(headers)
             |> post("/v1/tree/comments", %{
               "node_id" => node.id,
               "body_markdown" => "rate-limited first",
               "body_plaintext" => "rate-limited first"
             })
             |> json_response(201)

    assert node_id == node.id

    assert %{
             "error" => %{
               "code" => "comment_create_rate_limited",
               "retry_after_ms" => retry_after_ms
             }
           } =
             Phoenix.ConnTest.build_conn()
             |> with_siwa_headers(headers)
             |> post("/v1/tree/comments", %{
               "node_id" => node.id,
               "body_markdown" => "rate-limited second",
               "body_plaintext" => "rate-limited second"
             })
             |> json_response(429)

    assert is_integer(retry_after_ms)
    assert retry_after_ms > 0
  end

  test "comment create throttle is scoped per node", %{conn: conn} do
    headers = create_agent_headers!("comment-node-scope")
    first_node = create_node!(headers.agent, comments_locked: false)
    second_node = create_node!(headers.agent, comments_locked: false)

    assert %{"data" => %{"node_id" => first_node_id}} =
             conn
             |> with_siwa_headers(headers)
             |> post("/v1/tree/comments", %{
               "node_id" => first_node.id,
               "body_markdown" => "first node comment",
               "body_plaintext" => "first node comment"
             })
             |> json_response(201)

    assert first_node_id == first_node.id

    assert %{"data" => %{"node_id" => second_node_id}} =
             Phoenix.ConnTest.build_conn()
             |> with_siwa_headers(headers)
             |> post("/v1/tree/comments", %{
               "node_id" => second_node.id,
               "body_markdown" => "second node comment",
               "body_plaintext" => "second node comment"
             })
             |> json_response(201)

    assert second_node_id == second_node.id
  end

  defp create_agent_headers!(label_prefix, opts \\ []) do
    unique = System.unique_integer([:positive])

    wallet = random_eth_address()
    registry = random_eth_address()
    token_id = Integer.to_string(unique)

    agent =
      Agents.upsert_verified_agent!(%{
        "chain_id" => "8453",
        "registry_address" => registry,
        "token_id" => token_id,
        "wallet_address" => wallet,
        "label" => "#{label_prefix}-#{unique}",
        "status" => Keyword.get(opts, :status, "active")
      })

    %{agent: agent, wallet: wallet, chain_id: "8453", registry: registry, token_id: token_id}
  end

  defp with_siwa_headers(conn, headers) do
    TechTreeWeb.TestSupport.SiwaIntegrationSupport.with_siwa_headers(conn,
      wallet: headers.wallet,
      chain_id: headers.chain_id,
      registry_address: headers.registry,
      token_id: headers.token_id
    )
  end

  defp create_node!(creator, opts) do
    unique = System.unique_integer([:positive])

    %Node{}
    |> Ecto.Changeset.change(%{
      path: "n#{unique}",
      depth: 0,
      seed: "ML",
      kind: :hypothesis,
      title: "comment-node-#{unique}",
      status: Keyword.get(opts, :status, :anchored),
      notebook_source: "print('node')",
      publish_idempotency_key: "comment-node:#{unique}",
      comments_locked: Keyword.fetch!(opts, :comments_locked),
      creator_agent_id: creator.id
    })
    |> Repo.insert!()
  end

  defp random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end
end
