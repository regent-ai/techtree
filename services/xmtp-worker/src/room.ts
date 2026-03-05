import { loadConfig } from "./config.js";
import { getCanonicalRoom, upsertCanonicalRoom } from "./phoenix.js";
import type { CanonicalRoom } from "./types.js";

const config = loadConfig();

export const ensureCanonicalRoom = async (
  roomKey: string,
  xmtpGroupIdOverride?: string | null,
): Promise<CanonicalRoom> => {
  const existing = await getCanonicalRoom(roomKey);

  if (existing && existing.xmtpGroupId && existing.xmtpGroupId.length > 0) {
    return existing;
  }

  const xmtpGroupId =
    typeof xmtpGroupIdOverride === "string" && xmtpGroupIdOverride.length > 0
      ? xmtpGroupIdOverride
      : config.canonicalRoomGroupId;

  return upsertCanonicalRoom({
    room_key: roomKey,
    xmtp_group_id: xmtpGroupId,
    name: config.canonicalRoomName,
    status: "active",
  });
};
