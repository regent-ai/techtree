defmodule TechTree.PhaseDApiSupport do
  @moduledoc false

  import Plug.Conn

  alias TechTree.{Accounts, Agents, Nodes, Repo}
  alias TechTree.Nodes.Node
  alias TechTree.Trollbox.Message, as: TrollboxMessage

  @spec setup_privy_config!() :: %{
          app_id: String.t(),
          private_pem: String.t(),
          restore: (-> any())
        }
  def setup_privy_config! do
    original_privy_cfg = Application.get_env(:tech_tree, :privy, [])
    app_id = "privy-test-app-#{unique_suffix()}"
    {private_pem, public_pem} = generate_es256_pems()

    Application.put_env(:tech_tree, :privy,
      app_id: app_id,
      verification_key: public_pem
    )

    %{
      app_id: app_id,
      private_pem: private_pem,
      restore: fn -> Application.put_env(:tech_tree, :privy, original_privy_cfg) end
    }
  end

  @spec with_privy_bearer(Plug.Conn.t(), String.t(), String.t(), String.t()) :: Plug.Conn.t()
  def with_privy_bearer(conn, privy_user_id, app_id, private_pem) do
    token = privy_bearer_token(privy_user_id, app_id, private_pem)

    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer #{token}")
  end

  @spec with_siwa_headers(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def with_siwa_headers(conn, opts \\ []) do
    unique = unique_suffix()

    wallet = Keyword.get(opts, :wallet, random_eth_address())
    chain_id = Keyword.get(opts, :chain_id, "11155111")
    registry = Keyword.get(opts, :registry_address, random_eth_address())
    token_id = Keyword.get(opts, :token_id, Integer.to_string(unique))

    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("x-agent-wallet-address", wallet)
    |> put_req_header("x-agent-chain-id", chain_id)
    |> put_req_header("x-agent-registry-address", registry)
    |> put_req_header("x-agent-token-id", token_id)
  end

  @spec create_agent!(String.t(), keyword()) :: TechTree.Agents.AgentIdentity.t()
  def create_agent!(prefix, opts \\ []) do
    unique = unique_suffix()
    status = Keyword.get(opts, :status, "active")

    Agents.upsert_verified_agent!(%{
      "chain_id" => Keyword.get(opts, :chain_id, "11155111"),
      "registry_address" =>
        Keyword.get(opts, :registry_address, "0x#{prefix}-registry-#{unique}"),
      "token_id" => Keyword.get(opts, :token_id, Integer.to_string(unique)),
      "wallet_address" => Keyword.get(opts, :wallet_address, "0x#{prefix}-wallet-#{unique}"),
      "label" => "#{prefix}-#{unique}",
      "status" => status
    })
  end

  @spec create_human!(String.t(), keyword()) :: TechTree.Accounts.HumanUser.t()
  def create_human!(prefix, opts \\ []) do
    unique = unique_suffix()
    role = Keyword.get(opts, :role, "user")
    privy_user_id = "privy-#{prefix}-#{unique}"

    {:ok, human} =
      Accounts.upsert_human_by_privy_id(privy_user_id, %{
        "wallet_address" => Keyword.get(opts, :wallet_address, "0x#{prefix}-wallet-#{unique}"),
        "display_name" => Keyword.get(opts, :display_name, "#{prefix}-#{unique}"),
        "role" => role
      })

    human
  end

  @spec create_ready_node!(TechTree.Agents.AgentIdentity.t(), keyword()) :: Node.t()
  def create_ready_node!(creator, opts \\ []) do
    unique = unique_suffix()
    parent_id = Keyword.get(opts, :parent_id)

    path =
      case parent_id do
        nil -> "n#{unique}"
        id -> "n#{id}.n#{unique}"
      end

    %Node{}
    |> Ecto.Changeset.change(%{
      path: path,
      depth: if(parent_id, do: 1, else: 0),
      seed: Keyword.get(opts, :seed, "ML"),
      kind: Keyword.get(opts, :kind, :hypothesis),
      title: Keyword.get(opts, :title, "ready-node-#{unique}"),
      notebook_source: Keyword.get(opts, :notebook_source, "print('ready node')"),
      status: :anchored,
      parent_id: parent_id,
      creator_agent_id: creator.id,
      publish_idempotency_key: "node:#{unique}:phase-d"
    })
    |> Repo.insert!()
  end

  @spec mark_node_ready_for_public!(integer()) :: :ok
  def mark_node_ready_for_public!(node_id) do
    unique = unique_suffix()

    ready_result =
      Nodes.mark_node_anchored!(node_id, %{
        tx_hash: "0xtx-#{unique}",
        chain_id: 11_155_111,
        contract_address: "0xcontract-#{unique}",
        block_number: unique,
        log_index: 0
      })

    if ready_result in [:transitioned, :already_transitioned] do
      :ok
    else
      raise "failed to transition node #{node_id} to ready"
    end
  end

  @spec create_trollbox_message!(
          TechTree.Accounts.HumanUser.t() | TechTree.Agents.AgentIdentity.t(),
          map()
        ) ::
          TrollboxMessage.t()
  def create_trollbox_message!(author, attrs \\ %{})

  def create_trollbox_message!(%TechTree.Accounts.HumanUser{} = human, attrs) do
    %TrollboxMessage{}
    |> TrollboxMessage.changeset(%{
      author_kind: :human,
      author_scope: "human:#{human.id}",
      author_human_id: human.id,
      client_message_id: Map.get(attrs, :client_message_id),
      body: Map.get(attrs, :body, "trollbox-human-#{unique_suffix()}"),
      transport_msg_id: Map.get(attrs, :transport_msg_id, "transport-human-#{unique_suffix()}"),
      transport_topic: Map.get(attrs, :transport_topic, "trollbox:global"),
      reply_to_message_id: Map.get(attrs, :reply_to_message_id),
      reactions: Map.get(attrs, :reactions, %{}),
      moderation_state: Map.get(attrs, :moderation_state, "visible")
    })
    |> Repo.insert!()
    |> Repo.preload([:author_human, :author_agent])
  end

  def create_trollbox_message!(%TechTree.Agents.AgentIdentity{} = agent, attrs) do
    %TrollboxMessage{}
    |> TrollboxMessage.changeset(%{
      author_kind: :agent,
      author_scope: "agent:#{agent.id}",
      author_agent_id: agent.id,
      client_message_id: Map.get(attrs, :client_message_id),
      body: Map.get(attrs, :body, "trollbox-agent-#{unique_suffix()}"),
      transport_msg_id: Map.get(attrs, :transport_msg_id, "transport-agent-#{unique_suffix()}"),
      transport_topic: Map.get(attrs, :transport_topic, "trollbox:global"),
      reply_to_message_id: Map.get(attrs, :reply_to_message_id),
      reactions: Map.get(attrs, :reactions, %{}),
      moderation_state: Map.get(attrs, :moderation_state, "visible")
    })
    |> Repo.insert!()
    |> Repo.preload([:author_human, :author_agent])
  end

  @spec unique_suffix() :: integer()
  def unique_suffix do
    System.unique_integer([:positive, :monotonic])
  end

  @spec random_eth_address() :: String.t()
  def random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end

  @spec generate_es256_pems() :: {String.t(), String.t()}
  defp generate_es256_pems do
    private_jwk = JOSE.JWK.generate_key({:ec, "P-256"})
    public_jwk = JOSE.JWK.to_public(private_jwk)

    private_pem = private_jwk |> JOSE.JWK.to_pem() |> normalize_pem_output()
    public_pem = public_jwk |> JOSE.JWK.to_pem() |> normalize_pem_output()

    {private_pem, public_pem}
  end

  @spec normalize_pem_output(term()) :: String.t()
  defp normalize_pem_output({_, pem}), do: normalize_pem_output(pem)
  defp normalize_pem_output(pem) when is_binary(pem), do: pem
  defp normalize_pem_output(pem) when is_list(pem), do: IO.iodata_to_binary(pem)

  @spec privy_bearer_token(String.t(), String.t(), String.t()) :: String.t()
  defp privy_bearer_token(privy_user_id, app_id, private_pem) do
    now = System.system_time(:second)

    claims = %{
      "iss" => "privy.io",
      "sub" => privy_user_id,
      "aud" => app_id,
      "iat" => now,
      "exp" => now + 3600
    }

    private_jwk = JOSE.JWK.from_pem(private_pem)

    {_, token} =
      private_jwk
      |> JOSE.JWT.sign(%{"alg" => "ES256"}, claims)
      |> JOSE.JWS.compact()

    token
  end
end
