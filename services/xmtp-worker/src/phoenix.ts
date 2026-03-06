import { loadConfig } from "./config.js";
import type {
  CanonicalRoom,
  Decoder,
  MembershipCommand,
  MembershipOp,
  MembershipResolutionStatus,
  MirrorIngestPayload,
  MirrorResult,
  RoomEnsurePayload,
  TrollboxShard,
} from "./types.js";

interface RequestOptions {
  allowStatuses?: readonly number[];
  expectEnvelope?: boolean;
}

interface RoomWire {
  room_key: string;
  shard_key?: string;
  xmtp_group_id: string | null;
  name: string;
  status: string;
  presence_ttl_seconds?: number;
}

interface MembershipWire {
  id: number | string;
  op: MembershipOp;
  xmtp_inbox_id: string;
}

interface MirrorWire {
  id: number | string;
}

const config = loadConfig();

export class PhoenixApiError extends Error {
  readonly status: number;

  constructor(message: string, status: number) {
    super(message);
    this.name = "PhoenixApiError";
    this.status = status;
  }
}

export const isPhoenixApiError = (value: unknown): value is PhoenixApiError => {
  return value instanceof PhoenixApiError;
};

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === "object" && value !== null;
};

const getString = (value: unknown, fieldName: string): string => {
  if (typeof value === "string" && value.length > 0) return value;
  throw new Error(`invalid ${fieldName}`);
};

const getNullableString = (value: unknown, fieldName: string): string | null => {
  if (value === null || value === undefined) return null;
  if (typeof value === "string") return value;
  throw new Error(`invalid ${fieldName}`);
};

const decodeEnvelope = <T>(value: unknown, decode: Decoder<T>): T => {
  if (!isRecord(value)) {
    throw new Error("invalid response envelope");
  }

  if (!("data" in value)) {
    throw new Error("missing response data");
  }

  return decode((value as { data: unknown }).data);
};

const decodeRoom = (value: unknown): CanonicalRoom => {
  if (!isRecord(value)) {
    throw new Error("invalid room payload");
  }

  const room = value as Partial<RoomWire>;

  const presenceTtlSeconds =
    typeof room.presence_ttl_seconds === "number" && Number.isFinite(room.presence_ttl_seconds)
      ? Math.trunc(room.presence_ttl_seconds)
      : null;

  return {
    roomKey: getString(room.room_key, "room_key"),
    xmtpGroupId: getNullableString(room.xmtp_group_id, "xmtp_group_id"),
    name: getString(room.name, "name"),
    status: getString(room.status, "status"),
    ...(presenceTtlSeconds === null ? {} : { presenceTtlSeconds }),
  };
};

const decodeShards = (value: unknown): TrollboxShard[] => {
  if (!Array.isArray(value)) {
    throw new Error("invalid shard list payload");
  }

  return value.map((item) => {
    const decoded = decodeRoom(item);
    const record = isRecord(item) ? (item as Partial<RoomWire>) : {};
    const shardKeyCandidate =
      typeof record.shard_key === "string" && record.shard_key.length > 0
        ? record.shard_key
        : decoded.roomKey;

    return {
      ...decoded,
      shardKey: shardKeyCandidate,
    };
  });
};

const decodeMembershipCommand = (value: unknown): MembershipCommand | null => {
  if (value === null) return null;
  if (!isRecord(value)) {
    throw new Error("invalid membership command payload");
  }

  const command = value as Partial<MembershipWire>;
  const op = command.op;

  if (op !== "add_member" && op !== "remove_member") {
    throw new Error("invalid membership operation");
  }

  const id = String(command.id ?? "");
  if (id.length === 0) {
    throw new Error("invalid membership command id");
  }

  return {
    id,
    op,
    inboxId: getString(command.xmtp_inbox_id, "xmtp_inbox_id"),
  };
};

const decodeMirror = (value: unknown): MirrorResult => {
  if (!isRecord(value)) {
    return { ok: true, mirroredId: "" };
  }

  const mirror = value as Partial<MirrorWire>;
  return {
    ok: true,
    mirroredId: String(mirror.id ?? ""),
  };
};

const resolveTemplate = (template: string, value: string): string => {
  return template.replace(":id", encodeURIComponent(value));
};

const request = async <T>(
  endpoint: string,
  method: "GET" | "POST",
  decodeData: Decoder<T>,
  body?: unknown,
  options?: RequestOptions,
): Promise<T> => {
  const timeoutSignal = AbortSignal.timeout(config.requestTimeoutMs);
  const headers: Record<string, string> = {
    accept: "application/json",
  };

  if (method !== "GET") {
    headers["content-type"] = "application/json";
  }

  if (config.internalSharedSecret.length > 0) {
    headers["x-tech-tree-secret"] = config.internalSharedSecret;
  }

  const requestInit: RequestInit = {
    method,
    headers,
    signal: timeoutSignal,
  };

  if (body !== undefined) {
    requestInit.body = JSON.stringify(body);
  }

  const response = await fetch(endpoint, requestInit);

  const payload = (await response.json().catch(() => null)) as unknown;
  const allowedStatus = options?.allowStatuses ?? [];
  const allowedFailure = !response.ok && allowedStatus.includes(response.status);

  if (!response.ok && !allowedFailure) {
    throw new PhoenixApiError(`request failed status=${response.status}`, response.status);
  }

  if (options?.expectEnvelope === false) {
    return undefined as T;
  }

  if (allowedFailure) {
    try {
      return decodeEnvelope(payload, decodeData);
    } catch {
      return decodeData(null);
    }
  }

  return decodeEnvelope(payload, decodeData);
};

export const ensureCanonicalRoom = async (
  payload: RoomEnsurePayload,
): Promise<CanonicalRoom> => {
  return request(config.roomEnsureEndpoint, "POST", decodeRoom, payload);
};

export const listShardRooms = async (): Promise<TrollboxShard[]> => {
  return request(config.shardListEndpoint, "GET", decodeShards);
};

export const postMirroredMessage = async (
  payload: MirrorIngestPayload,
): Promise<MirrorResult> => {
  try {
    const mirrored = await request(config.messageIngestEndpoint, "POST", decodeMirror, payload, {
      allowStatuses: [409],
    });

    if (mirrored.mirroredId.length > 0) {
      return mirrored;
    }

    return { ok: true, mirroredId: payload.xmtp_message_id };
  } catch (error) {
    if (isPhoenixApiError(error) && error.status === 409) {
      return { ok: true, mirroredId: payload.xmtp_message_id, deduped: true };
    }

    throw error;
  }
};

export const leaseMembershipCommand = async (
  roomKey: string,
): Promise<MembershipCommand | null> => {
  return request(config.leaseMembershipEndpoint, "POST", decodeMembershipCommand, {
    room_key: roomKey,
  });
};

export const resolveMembershipCommand = async (
  commandId: string,
  status: MembershipResolutionStatus,
  error?: string,
): Promise<void> => {
  const endpoint = resolveTemplate(config.resolveMembershipEndpointTemplate, commandId);
  const payload: { status: MembershipResolutionStatus; error?: string } =
    status === "failed"
      ? typeof error === "string"
        ? { status, error }
        : { status }
      : { status };

  await request(endpoint, "POST", () => undefined, payload, {
    allowStatuses: [404, 409],
    expectEnvelope: false,
  });
};
