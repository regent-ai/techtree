export type StreamSource = "xmtp";
export type MembershipOp = "add_member" | "remove_member";
export type SenderType = "human" | "agent" | "system";
export type TransportMode = "auto" | "mock" | "real";
export type RuntimeTransportMode = "mock" | "real";

export interface IngestionMessageEvent {
  kind: "message";
  source: StreamSource;
  id: string;
  receivedAtMs: number;
  payload: {
    topic: string;
    sender: string;
    body: string;
  };
}

export interface IngestionHeartbeatEvent {
  kind: "heartbeat";
  source: StreamSource;
  id: string;
  receivedAtMs: number;
  payload: {
    lagMs: number;
  };
}

export type IngestionEvent = IngestionMessageEvent | IngestionHeartbeatEvent;

export interface MirrorResult {
  ok: true;
  mirroredId: string;
  deduped?: boolean;
}

export interface MembershipCommand {
  id: string;
  op: MembershipOp;
  inboxId: string;
}

export interface CanonicalRoom {
  roomKey: string;
  xmtpGroupId: string | null;
  name: string;
  status: string;
}

export interface RoomUpsertPayload {
  room_key: string;
  xmtp_group_id: string;
  name: string;
  status: "active" | "inactive";
}

export interface MirrorUpsertPayload {
  room_key: string;
  xmtp_message_id: string;
  sender_inbox_id: string;
  sender_wallet_address: string | null;
  sender_label: string | null;
  sender_type: SenderType;
  body: string;
  sent_at: string;
  raw_payload: {
    source: StreamSource;
    topic: string;
    sender: string;
    body: string;
    receivedAtMs: number;
  };
}

export interface PhoenixApiErrorPayload {
  message?: string;
}

export interface PhoenixApiEnvelope<T> {
  data: T;
  code?: string;
  ok?: boolean;
  error?: PhoenixApiErrorPayload;
}

export type Decoder<T> = (value: unknown) => T;

export interface WorkerConfig {
  pollIntervalMs: number;
  requestTimeoutMs: number;
  transportMode: TransportMode;
  realTransportModule: string | null;
  xmtpEnv: "dev" | "production";
  xmtpSdkModule: string;
  xmtpEthersModule: string;
  xmtpDbEncryptionKey: string | null;
  xmtpWalletPrivateKey: string | null;
  xmtpConsentProofEndpoint: string | null;
  xmtpRequireConsent: boolean;
  xmtpCreateGroupIfMissing: boolean;
  mockMessageEveryHeartbeats: number;
  membershipLeaseBatchSize: number;
  membershipCommandCacheTtlMs: number;
  canonicalRoomKey: string;
  canonicalRoomName: string;
  canonicalRoomGroupId: string;
  internalSharedSecret: string;
  roomLookupEndpointTemplate: string;
  roomUpsertEndpoint: string;
  mirrorEndpoint: string;
  leaseMembershipEndpoint: string;
  completeMembershipEndpointTemplate: string;
  failMembershipEndpointTemplate: string;
}

export interface CreateEventStreamOptions {
  signal: AbortSignal;
  pollIntervalMs: number;
}

export interface MembershipApplyInput {
  room: CanonicalRoom;
  command: MembershipCommand;
}

export type MembershipApplyResult =
  | {
      status: "applied";
    }
  | {
      status: "noop";
      reason: "already_member" | "not_member";
    };

export interface IngestionTransport {
  readonly mode: RuntimeTransportMode;
  readonly name: string;
  getCanonicalGroupId?(): Promise<string | null> | string | null;
  createEventStream(options: CreateEventStreamOptions): AsyncIterable<IngestionEvent>;
  applyMembershipCommand(input: MembershipApplyInput): Promise<MembershipApplyResult>;
}

export interface RealTransportFactoryModule {
  createTransport(config: WorkerConfig): Promise<IngestionTransport> | IngestionTransport;
}

export interface SyncLoopOptions {
  signal: AbortSignal;
  stream: AsyncIterable<IngestionEvent>;
  onEvent: (event: IngestionEvent) => Promise<void>;
  onError?: (error: unknown) => Promise<void> | void;
}
