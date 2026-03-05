import { loadConfig } from "./config.js";
import type {
  CanonicalRoom,
  Decoder,
  MembershipCommand,
  MembershipOp,
  MirrorResult,
  MirrorUpsertPayload,
  RoomUpsertPayload,
} from "./types.js";

interface RequestOptions {
  allowStatuses?: readonly number[];
  expectEnvelope?: boolean;
}

interface RoomWire {
  room_key: string;
  xmtp_group_id: string | null;
  name: string;
  status: string;
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

  return {
    roomKey: getString(room.room_key, "room_key"),
    xmtpGroupId: getNullableString(room.xmtp_group_id, "xmtp_group_id"),
    name: getString(room.name, "name"),
    status: getString(room.status, "status"),
  };
};

const decodeOptionalRoom = (value: unknown): CanonicalRoom | null => {
  if (value === null) return null;
  return decodeRoom(value);
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
  return template.replace(":id", encodeURIComponent(value)).replace(":roomKey", encodeURIComponent(value));
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

export const getCanonicalRoom = async (roomKey: string): Promise<CanonicalRoom | null> => {
  const endpoint = resolveTemplate(config.roomLookupEndpointTemplate, roomKey);
  return request(endpoint, "GET", decodeOptionalRoom);
};

export const upsertCanonicalRoom = async (
  payload: RoomUpsertPayload,
): Promise<CanonicalRoom> => {
  return request(config.roomUpsertEndpoint, "POST", decodeRoom, payload);
};

export const postMirroredMessage = async (
  payload: MirrorUpsertPayload,
): Promise<MirrorResult> => {
  try {
    const mirrored = await request(config.mirrorEndpoint, "POST", decodeMirror, payload, {
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

export const completeMembershipCommand = async (commandId: string): Promise<void> => {
  const endpoint = resolveTemplate(config.completeMembershipEndpointTemplate, commandId);
  await request(endpoint, "POST", () => undefined, undefined, {
    allowStatuses: [404, 409],
    expectEnvelope: false,
  });
};

export const failMembershipCommand = async (
  commandId: string,
  message: string,
): Promise<void> => {
  const endpoint = resolveTemplate(config.failMembershipEndpointTemplate, commandId);
  await request(
    endpoint,
    "POST",
    () => undefined,
    { error: message },
    { allowStatuses: [404, 409], expectEnvelope: false },
  );
};
