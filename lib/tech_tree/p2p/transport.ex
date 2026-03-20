defmodule TechTree.P2P.Transport do
  @moduledoc false

  use GenServer

  alias Libp2p.{Gossipsub, Identity, PeerId, Protocol, Swarm}
  alias TechTree.P2P.{Bootstrapper, Envelope, IdentityStore, MsgId}

  @global_room "global"
  @health_check_interval 2_000

  @type status_map :: %{
          mode: :libp2p | :local_only | :degraded,
          ready?: boolean(),
          peer_count: non_neg_integer(),
          subscriptions: [binary()],
          last_error: binary() | nil,
          local_peer_id: binary() | nil,
          origin_node_id: binary() | nil
        }

  @callback publish(binary(), map()) :: :ok | {:error, term()}
  @callback subscribe(binary()) :: :ok | {:error, term()}
  @callback status() :: status_map()

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec status() :: status_map()
  def status do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> GenServer.call(pid, :status)
      _ -> disabled_status()
    end
  end

  @spec subscribe(binary()) :: :ok | {:error, term()}
  def subscribe(room_id) when is_binary(room_id) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> GenServer.call(pid, {:subscribe, room_id})
      _ -> {:error, :disabled}
    end
  end

  @spec publish(binary(), map()) :: :ok | {:error, term()}
  def publish(topic, payload) when is_binary(topic) and is_map(payload) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> GenServer.call(pid, {:publish, topic, payload})
      _ -> {:error, :disabled}
    end
  end

  @spec topic_for_room(binary()) :: binary()
  def topic_for_room(@global_room) do
    "#{config()[:topic_prefix]}.global"
  end

  def topic_for_room("agent:" <> agent_id) do
    "#{config()[:topic_prefix]}.agent.#{agent_id}"
  end

  def topic_for_room(room_id), do: "#{config()[:topic_prefix]}.#{room_id}"

  @spec origin_node_id() :: binary()
  def origin_node_id, do: config()[:origin_node_id]

  @spec local_peer_id_base58() :: binary() | nil
  def local_peer_id_base58 do
    case status() do
      %{local_peer_id: local_peer_id} -> local_peer_id
      _ -> nil
    end
  end

  @spec build_and_publish(binary(), TechTree.Trollbox.Message.t()) :: :ok | {:error, term()}
  def build_and_publish(event, message) do
    case safe_identity() do
      {:ok, %Identity{} = identity} ->
        topic = topic_for_room(message.room_id || @global_room)
        payload = Envelope.build(event, topic, message, identity, origin_node_id())
        publish(topic, payload)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec handle_gossip(binary(), binary(), binary()) :: :ok
  def handle_gossip(topic, data, from_peer_id) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        GenServer.cast(pid, {:handle_gossip, topic, data, from_peer_id})

      _ ->
        :ok
    end
  end

  @impl true
  def init(_opts) do
    if config()[:enabled] do
      identity = IdentityStore.load_or_create!(config()[:identity_path])
      local_peer_id = PeerId.to_base58(identity.peer_id)
      {:ok, core_sup} = Supervisor.start_link(core_children(identity), strategy: :one_for_one)
      subscriptions = MapSet.new([@global_room])

      st = %{
        enabled?: true,
        identity: identity,
        core_sup: core_sup,
        subscriptions: subscriptions,
        ready_peers: MapSet.new(),
        peer_identities: %{},
        last_error: nil,
        listener_started?: false,
        health_interval_ms: config()[:health_interval_ms] || @health_check_interval,
        local_peer_id: local_peer_id
      }

      send(self(), :bootstrap)
      {:ok, st}
    else
      {:ok,
       %{
         enabled?: false,
         identity: nil,
         core_sup: nil,
         subscriptions: MapSet.new(),
         ready_peers: MapSet.new(),
         peer_identities: %{},
         last_error: nil,
         listener_started?: false,
         health_interval_ms: config()[:health_interval_ms] || @health_check_interval,
         local_peer_id: nil
       }}
    end
  end

  @impl true
  def handle_call(:status, _from, st) do
    {:reply, current_status(st), st}
  end

  def handle_call(:identity, _from, %{enabled?: true, identity: identity} = st) do
    {:reply, {:ok, identity}, st}
  end

  def handle_call(:identity, _from, st) do
    {:reply, {:error, :disabled}, st}
  end

  def handle_call({:subscribe, _room_id}, _from, %{enabled?: false} = st) do
    {:reply, {:error, :disabled}, st}
  end

  def handle_call({:subscribe, room_id}, _from, st) do
    topic = topic_for_room(room_id)
    :ok = Gossipsub.subscribe(gossipsub_name(), topic)
    {:reply, :ok, %{st | subscriptions: MapSet.put(st.subscriptions, room_id)}}
  end

  def handle_call({:publish, _topic, _payload}, _from, %{enabled?: false} = st) do
    {:reply, {:error, :disabled}, st}
  end

  def handle_call({:publish, topic, payload}, _from, st) do
    :ok = Gossipsub.publish(gossipsub_name(), topic, Envelope.encode!(payload))
    {:reply, :ok, st}
  end

  @impl true
  def handle_cast({:handle_gossip, topic, data, from_peer_id}, st) do
    st =
      case Envelope.decode(data) do
        {:ok, payload} ->
          handle_inbound_payload(st, topic, payload, from_peer_id)

        {:error, reason} ->
          %{st | last_error: "invalid gossip payload: #{inspect(reason)}"}
      end

    {:noreply, st}
  end

  @impl true
  def handle_info(:bootstrap, st) do
    st =
      st
      |> listen_once()
      |> subscribe_rooms()
      |> dial_bootstrap_peers()

    schedule_health(st.health_interval_ms)
    {:noreply, st}
  end

  def handle_info(:health_check, st) do
    st = dial_bootstrap_peers(st)
    schedule_health(st.health_interval_ms)
    {:noreply, st}
  end

  def handle_info({:gossipsub_outbound_ready, peer_id, _stream_id}, st) do
    {:noreply,
     %{st | ready_peers: MapSet.put(st.ready_peers, PeerId.to_base58(peer_id)), last_error: nil}}
  end

  def handle_info({:gossipsub_outbound_failed, peer_id, reason}, st) do
    peer = PeerId.to_base58(peer_id)

    {:noreply,
     %{
       st
       | ready_peers: MapSet.delete(st.ready_peers, peer),
         last_error: "peer #{peer} failed: #{inspect(reason)}"
     }}
  end

  def handle_info(_msg, st), do: {:noreply, st}

  defp safe_identity do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        GenServer.call(pid, :identity)

      _ ->
        {:error, :disabled}
    end
  end

  defp config, do: Application.fetch_env!(:tech_tree, TechTree.P2P)

  defp core_children(identity) do
    [
      {Registry, keys: :unique, name: Libp2p.PeerRegistry},
      {Libp2p.PeerStore, name: peer_store_name()},
      {Libp2p.PeerSessionSupervisor, name: Libp2p.PeerSessionSupervisor},
      {DynamicSupervisor, name: Libp2p.ConnectionSupervisor, strategy: :one_for_one},
      {Task.Supervisor, name: Libp2p.RpcStreamSupervisor},
      {Libp2p.Gossipsub,
       name: gossipsub_name(),
       on_message: &__MODULE__.handle_gossip/3,
       msg_id_fn: &MsgId.from_topic_and_data/2,
       event_sink: self()},
      {Libp2p.Swarm,
       [
         name: swarm_name(),
         peer_store: peer_store_name(),
         connection_supervisor: Libp2p.ConnectionSupervisor,
         peer_session_supervisor: Libp2p.PeerSessionSupervisor,
         identity: identity,
         gossipsub: gossipsub_name(),
         protocol_handlers: %{
           Protocol.identify() => Libp2p.Identify,
           Protocol.identify_push() => Libp2p.Identify,
           Protocol.gossipsub_1_1() => fn conn, stream_id, initial ->
             Libp2p.Gossipsub.handle_inbound(gossipsub_name(), conn, stream_id, initial)
           end
         }
       ]}
    ]
  end

  defp listen_once(%{listener_started?: true} = st), do: st

  defp listen_once(st) do
    case Swarm.listen(swarm_name(), config()[:listen_ip], config()[:listen_port]) do
      {:ok, _listener} -> %{st | listener_started?: true}
      {:error, reason} -> %{st | last_error: "listen failed: #{inspect(reason)}"}
    end
  end

  defp subscribe_rooms(st) do
    Enum.each(st.subscriptions, fn room_id ->
      :ok = Gossipsub.subscribe(gossipsub_name(), topic_for_room(room_id))
    end)

    st
  end

  defp dial_bootstrap_peers(%{enabled?: false} = st), do: st

  defp dial_bootstrap_peers(st) do
    Enum.reduce(config()[:bootstrap_peers] || [], st, fn raw_peer, acc ->
      case Bootstrapper.parse_peer(raw_peer) do
        {:ok, peer} ->
          case Swarm.dial(swarm_name(), peer.ip, peer.port, timeout: 5_000) do
            {:ok, _conn} ->
              maybe_await_peer(acc, peer)

            {:error, reason} ->
              %{acc | last_error: "dial failed for #{raw_peer}: #{inspect(reason)}"}
          end

        {:error, reason} ->
          %{acc | last_error: "invalid bootstrap peer #{raw_peer}: #{inspect(reason)}"}
      end
    end)
  end

  defp maybe_await_peer(st, %{peer_id: nil}), do: st

  defp maybe_await_peer(st, %{peer_id: peer_id}) do
    case Gossipsub.await_peer(gossipsub_name(), peer_id, 2_000) do
      :ok ->
        %{st | ready_peers: MapSet.put(st.ready_peers, PeerId.to_base58(peer_id))}

      {:error, reason} ->
        %{st | last_error: "await_peer failed: #{inspect(reason)}"}
    end
  end

  defp handle_inbound_payload(st, topic, payload, from_peer_id) do
    allowed? =
      case config()[:allowed_peer_ids] || [] do
        [] -> true
        allowed -> PeerId.to_base58(from_peer_id) in allowed
      end

    local_peer = st.local_peer_id

    cond do
      not allowed? ->
        %{st | last_error: "rejected disallowed peer #{PeerId.to_base58(from_peer_id)}"}

      payload["origin_peer_id"] == local_peer ->
        st

      byte_size(Envelope.encode!(payload)) > config()[:max_message_bytes] ->
        %{st | last_error: "rejected oversized mesh payload"}

      true ->
        peer_id = PeerId.to_base58(from_peer_id)

        case verify_and_ingest(topic, payload, peer_id) do
          :ok -> st
          {:error, reason} -> %{st | last_error: "ingest failed: #{inspect(reason)}"}
        end
    end
  end

  defp verify_and_ingest(topic, payload, peer_id) do
    case payload do
      %{"origin_peer_id" => ^peer_id} ->
        case Envelope.verify(payload) do
          :ok -> TechTree.Trollbox.ingest_transport_event(topic, payload)
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :peer_id_mismatch}
    end
  end

  defp current_status(%{enabled?: false} = st) do
    %{disabled_status() | last_error: st.last_error}
  end

  defp current_status(st) do
    peer_count = MapSet.size(st.ready_peers)
    ready? = st.listener_started? and peer_count >= config()[:min_ready_peers]

    %{
      mode: if(ready?, do: :libp2p, else: :degraded),
      ready?: ready?,
      peer_count: peer_count,
      subscriptions: st.subscriptions |> Enum.map(&topic_for_room/1) |> Enum.sort(),
      last_error: st.last_error,
      local_peer_id: st.local_peer_id,
      origin_node_id: origin_node_id()
    }
  end

  defp schedule_health(interval_ms) do
    Process.send_after(self(), :health_check, interval_ms)
  end

  defp disabled_status do
    %{
      mode: :local_only,
      ready?: false,
      peer_count: 0,
      subscriptions: [],
      last_error: nil,
      local_peer_id: nil,
      origin_node_id: origin_node_id()
    }
  end

  defp peer_store_name, do: Libp2p.PeerStore
  defp swarm_name, do: __MODULE__.Swarm
  defp gossipsub_name, do: __MODULE__.Gossipsub
end
