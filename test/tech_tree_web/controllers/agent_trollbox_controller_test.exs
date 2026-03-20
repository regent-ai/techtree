defmodule TechTreeWeb.AgentTrollboxControllerTest do
  use TechTreeWeb.ConnCase, async: false

  import TechTree.PhaseDApiSupport

  alias Phoenix.Socket.Broadcast
  alias TechTree.Agents
  alias TechTree.Trollbox

  test "requires SIWA auth", %{conn: conn} do
    response =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/v1/agent/trollbox/messages", %{})
      |> json_response(401)

    assert %{"error" => %{"code" => "agent_auth_required"}} = response
  end

  test "creates and broadcasts trollbox messages for active agents", %{conn: conn} do
    Phoenix.PubSub.subscribe(TechTree.PubSub, Trollbox.channel_topic())

    wallet = random_eth_address()
    registry = random_eth_address()
    token_id = Integer.to_string(unique_suffix())

    agent_conn =
      conn
      |> with_siwa_headers(
        wallet: wallet,
        chain_id: "11155111",
        registry_address: registry,
        token_id: token_id
      )

    assert %{"data" => %{"id" => message_id, "author_kind" => "agent"}} =
             agent_conn
             |> post("/v1/agent/trollbox/messages", %{
               "body" => "agent live message",
               "client_message_id" => "agent-post-1"
             })
             |> json_response(201)

    assert_receive %Broadcast{
      topic: "trollbox:public",
      event: "message.created",
      payload: %{message: %{id: ^message_id, author_kind: "agent"}}
    }
  end

  test "supports idempotent retries for agent messages", %{conn: conn} do
    wallet = random_eth_address()
    registry = random_eth_address()
    token_id = Integer.to_string(unique_suffix())

    agent_conn =
      conn
      |> with_siwa_headers(
        wallet: wallet,
        chain_id: "11155111",
        registry_address: registry,
        token_id: token_id
      )

    payload = %{"body" => "agent repeat", "client_message_id" => "agent-post-2"}

    assert %{"data" => %{"id" => message_id}} =
             agent_conn
             |> post("/v1/agent/trollbox/messages", payload)
             |> json_response(201)

    assert %{"data" => %{"id" => ^message_id, "body" => "agent repeat"}} =
             Phoenix.ConnTest.build_conn()
             |> with_siwa_headers(
               wallet: wallet,
               chain_id: "11155111",
               registry_address: registry,
               token_id: token_id
             )
             |> post("/v1/agent/trollbox/messages", %{
               "body" => "agent repeat updated",
               "client_message_id" => "agent-post-2"
             })
             |> json_response(200)
  end

  test "lists agent-room history separately from the global room", %{conn: conn} do
    wallet = random_eth_address()
    registry = random_eth_address()
    token_id = Integer.to_string(unique_suffix())

    agent_conn =
      conn
      |> with_siwa_headers(
        wallet: wallet,
        chain_id: "11155111",
        registry_address: registry,
        token_id: token_id
      )

    assert %{"data" => %{"room_id" => "agent:" <> _agent_room_id, "body" => "private agent room"}} =
             agent_conn
             |> post("/v1/agent/trollbox/messages", %{
               "body" => "private agent room",
               "client_message_id" => "agent-room-1",
               "room" => "agent"
             })
             |> json_response(201)

    assert %{"data" => [%{"body" => "private agent room", "room_id" => "agent:" <> _}]} =
             agent_conn
             |> get("/v1/agent/trollbox/messages", %{"room" => "agent", "limit" => "10"})
             |> json_response(200)

    assert %{"data" => messages} =
             agent_conn
             |> get("/v1/agent/trollbox/messages", %{"limit" => "10"})
             |> json_response(200)

    refute Enum.any?(messages, &(&1["body"] == "private agent room"))
  end

  test "reacts to trollbox messages for active agents", %{conn: conn} do
    wallet = random_eth_address()
    registry = random_eth_address()
    token_id = Integer.to_string(unique_suffix())

    agent =
      Agents.upsert_verified_agent!(%{
        "chain_id" => "11155111",
        "registry_address" => registry,
        "token_id" => token_id,
        "wallet_address" => wallet,
        "label" => "agent-reactor"
      })

    message = create_trollbox_message!(create_human!("react-target"), %{body: "react target"})
    message_id = message.id

    assert %{"data" => %{"id" => ^message_id, "reactions" => %{"🔥" => 1}}} =
             conn
             |> with_siwa_headers(
               wallet: agent.wallet_address,
               chain_id: Integer.to_string(agent.chain_id),
               registry_address: agent.registry_address,
               token_id: Decimal.to_string(agent.token_id)
             )
             |> post("/v1/agent/trollbox/messages/#{message.id}/reactions", %{"emoji" => "🔥"})
             |> json_response(200)
  end

  test "rate limits agent trollbox bursts and repeated reactions", %{conn: conn} do
    wallet = random_eth_address()
    registry = random_eth_address()
    token_id = Integer.to_string(unique_suffix())

    agent_conn =
      conn
      |> with_siwa_headers(
        wallet: wallet,
        chain_id: "11155111",
        registry_address: registry,
        token_id: token_id
      )

    Enum.each(1..6, fn index ->
      body = "agent-burst-#{index}"

      assert %{"data" => %{"body" => ^body}} =
               agent_conn
               |> post("/v1/agent/trollbox/messages", %{"body" => body})
               |> json_response(201)
    end)

    assert %{"error" => %{"code" => "message_rate_limited", "retry_after_ms" => retry_after_ms}} =
             agent_conn
             |> post("/v1/agent/trollbox/messages", %{"body" => "agent-burst-7"})
             |> json_response(429)

    assert is_integer(retry_after_ms)
    assert retry_after_ms > 0
  end

  test "banned agents are rejected", %{conn: conn} do
    wallet = random_eth_address()
    registry = random_eth_address()
    token_id = Integer.to_string(unique_suffix())

    _agent =
      Agents.upsert_verified_agent!(%{
        "chain_id" => "11155111",
        "registry_address" => registry,
        "token_id" => token_id,
        "wallet_address" => wallet,
        "label" => "agent-banned",
        "status" => "banned"
      })

    assert %{"error" => %{"code" => "agent_banned"}} =
             conn
             |> with_siwa_headers(
               wallet: wallet,
               chain_id: "11155111",
               registry_address: registry,
               token_id: token_id
             )
             |> post("/v1/agent/trollbox/messages", %{"body" => "blocked"})
             |> json_response(403)
  end
end
