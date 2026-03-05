import { loadConfig } from "./config.js";
import { postMirroredMessage } from "./phoenix.js";
import type { IngestionMessageEvent, MirrorResult } from "./types.js";

const config = loadConfig();

export const mirrorMessage = async (event: IngestionMessageEvent): Promise<MirrorResult> => {
  return postMirroredMessage({
    room_key: config.canonicalRoomKey,
    xmtp_message_id: event.id,
    sender_inbox_id: event.payload.sender,
    sender_wallet_address: null,
    sender_label: null,
    sender_type: "human",
    body: event.payload.body,
    sent_at: new Date(event.receivedAtMs).toISOString(),
    raw_payload: {
      source: event.source,
      topic: event.payload.topic,
      sender: event.payload.sender,
      body: event.payload.body,
      receivedAtMs: event.receivedAtMs,
    },
  });
};
