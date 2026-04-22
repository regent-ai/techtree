defmodule TechTree.Chatbox.Actor do
  @moduledoc false

  alias TechTree.Accounts.HumanUser
  alias TechTree.Agents.AgentIdentity
  alias TechTree.XmtpIdentity

  @spec ensure_can_post(HumanUser.t() | AgentIdentity.t()) ::
          :ok | {:error, :human_banned | :agent_banned | :xmtp_identity_required}
  def ensure_can_post(%HumanUser{role: "banned"}), do: {:error, :human_banned}
  def ensure_can_post(%HumanUser{} = human), do: require_human_identity(human)

  def ensure_can_post(%AgentIdentity{status: status}) when status in ["banned", "inactive"] do
    {:error, :agent_banned}
  end

  def ensure_can_post(%AgentIdentity{}), do: :ok

  @spec ensure_can_react(HumanUser.t() | AgentIdentity.t()) ::
          :ok | {:error, :human_banned | :agent_banned | :xmtp_identity_required}
  def ensure_can_react(%HumanUser{role: "banned"}), do: {:error, :human_banned}
  def ensure_can_react(%HumanUser{} = human), do: require_human_identity(human)

  def ensure_can_react(%AgentIdentity{status: status}) when status in ["banned", "inactive"] do
    {:error, :agent_banned}
  end

  def ensure_can_react(%AgentIdentity{}), do: :ok

  @spec author_scope(:human | :agent, HumanUser.t() | AgentIdentity.t()) :: String.t()
  def author_scope(:human, %HumanUser{id: id}), do: "human:#{id}"
  def author_scope(:agent, %AgentIdentity{id: id}), do: "agent:#{id}"

  @spec actor_identity(HumanUser.t() | AgentIdentity.t()) :: {:human | :agent, integer()}
  def actor_identity(%HumanUser{id: id}), do: {:human, id}
  def actor_identity(%AgentIdentity{id: id}), do: {:agent, id}

  @spec put_author_fields(map(), :human | :agent, HumanUser.t() | AgentIdentity.t()) :: map()
  def put_author_fields(attrs, :human, %HumanUser{} = human) do
    attrs
    |> Map.put(:author_human_id, human.id)
    |> Map.put(:author_transport_id, "human:#{human.id}")
    |> Map.put(:author_display_name_snapshot, human.display_name)
    |> Map.put(:author_wallet_address_snapshot, human.wallet_address)
  end

  def put_author_fields(attrs, :agent, %AgentIdentity{} = agent) do
    attrs
    |> Map.put(:author_agent_id, agent.id)
    |> Map.put(:author_transport_id, "agent:#{agent.id}")
    |> Map.put(:author_label_snapshot, agent.label)
    |> Map.put(:author_wallet_address_snapshot, agent.wallet_address)
  end

  defp require_human_identity(%HumanUser{} = human) do
    case XmtpIdentity.ready_inbox_id(human) do
      {:ok, _inbox_id} -> :ok
      {:error, :wallet_address_required} -> {:error, :xmtp_identity_required}
      {:error, :xmtp_identity_required} -> {:error, :xmtp_identity_required}
    end
  end
end
