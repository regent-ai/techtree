import { loadConfig } from "./config.js";
import { postMirroredMessage } from "./phoenix.js";
import type { IngestionMessageEvent, MirrorResult } from "./types.js";

const config = loadConfig();

export const mirrorMessage = async (event: IngestionMessageEvent): Promise<MirrorResult> => {
  const roomKey =
    typeof event.payload.roomKey === "string" && event.payload.roomKey.length > 0
      ? event.payload.roomKey
      : config.canonicalRoomKey;

  return postMirroredMessage({
    room_key: roomKey,
    xmtp_message_id: event.id,
    sender_inbox_id: event.payload.sender,
    sender_wallet_address: null,
    sender_label: null,
    sender_type: "human",
    body: event.payload.body,
    sent_at: new Date(event.receivedAtMs).toISOString(),
    reply_to_message_id: event.payload.replyToMessageId ?? null,
    reactions: event.payload.reactions ?? {},
    raw_payload: {
      source: event.source,
      topic: event.payload.topic,
      roomKey,
      replyToMessageId: event.payload.replyToMessageId ?? null,
      reactions: event.payload.reactions ?? {},
      sender: event.payload.sender,
      body: event.payload.body,
      receivedAtMs: event.receivedAtMs,
    },
  });
};
