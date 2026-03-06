import { loadConfig } from "./config.js";
import { ensureCanonicalRoom as ensurePhoenixRoom } from "./phoenix.js";
import type { CanonicalRoom } from "./types.js";

const config = loadConfig();

export const ensureCanonicalRoom = async (
  roomKey: string,
  xmtpGroupIdOverride?: string | null,
  presenceTtlSeconds?: number,
): Promise<CanonicalRoom> => {
  const xmtpGroupId =
    typeof xmtpGroupIdOverride === "string" && xmtpGroupIdOverride.length > 0
      ? xmtpGroupIdOverride
      : config.canonicalRoomGroupId;

  return ensurePhoenixRoom({
    room_key: roomKey,
    xmtp_group_id: xmtpGroupId,
    name: config.canonicalRoomName,
    status: "active",
    ...(
      typeof presenceTtlSeconds === "number" && Number.isFinite(presenceTtlSeconds)
        ? {presence_ttl_seconds: Math.max(15, Math.trunc(presenceTtlSeconds))}
        : {}
    ),
  });
};
