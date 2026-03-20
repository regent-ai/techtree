import type { TransportStatus } from "./runtime.js";

export interface GossipsubStatus extends TransportStatus {
  note?: string;
  eventSocketPath?: string | null;
}

export interface GossipsubCommandResult {
  ok: false;
  code: "not_implemented";
  message: string;
}

export interface TrollboxLiveEvent {
  event: "message.created" | "message.updated" | "reaction.updated" | "message.hidden";
  message: import("./techtree.js").TrollboxMessage;
}
