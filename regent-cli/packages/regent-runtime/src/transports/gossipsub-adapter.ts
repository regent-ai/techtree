import type { GossipsubStatus, RegentConfig, TrollboxLiveEvent } from "@regent/types";

import { RegentError } from "../errors.js";
import type { TechtreeClient } from "../techtree/client.js";

type TrollboxListener = (event: TrollboxLiveEvent) => void;
type TrollboxRoom = "global" | "agent";

const isTrollboxLiveEvent = (payload: unknown): payload is TrollboxLiveEvent => {
  if (!payload || typeof payload !== "object") {
    return false;
  }

  const candidate = payload as Partial<TrollboxLiveEvent>;
  return typeof candidate.event === "string" && !!candidate.message && typeof candidate.message === "object";
};

export interface GossipsubAdapter {
  start(): Promise<void>;
  stop(): Promise<void>;
  status(): Promise<GossipsubStatus>;
  subscribeTrollbox(listener: TrollboxListener, room?: TrollboxRoom): Promise<() => void>;
}

export class PublicTrollboxRelayAdapter implements GossipsubAdapter {
  private readonly config: RegentConfig["gossipsub"];
  private readonly techtree: TechtreeClient;
  private readonly eventSocketPath: string;
  private currentStatus: GossipsubStatus;
  private readonly activeStreams = new Set<AbortController>();

  constructor(config: RegentConfig["gossipsub"], techtree: TechtreeClient, eventSocketPath: string) {
    this.config = config;
    this.techtree = techtree;
    this.eventSocketPath = eventSocketPath;
    this.currentStatus = this.baseStatus("stopped");
  }

  async start(): Promise<void> {
    if (!this.config.enabled) {
      this.currentStatus = this.baseStatus("disabled");
      return;
    }

    await this.refreshStatus();
  }

  async stop(): Promise<void> {
    for (const controller of this.activeStreams) {
      controller.abort();
    }

    this.activeStreams.clear();
    this.currentStatus = this.baseStatus(this.config.enabled ? "stopped" : "disabled");
  }

  async status(): Promise<GossipsubStatus> {
    if (!this.config.enabled) {
      return this.baseStatus("disabled");
    }

    await this.refreshStatus();
    return this.currentStatus;
  }

  async subscribeTrollbox(listener: TrollboxListener, room: TrollboxRoom = "global"): Promise<() => void> {
    if (!this.config.enabled) {
      throw new RegentError("trollbox_relay_disabled", "trollbox transport is disabled in config");
    }

    await this.refreshStatus();
    const controller = new AbortController();
    this.activeStreams.add(controller);
    this.currentStatus = {
      ...this.currentStatus,
      connected: true,
      eventSocketPath: this.eventSocketPath,
    };

    void this.techtree
      .streamTrollbox(room, (payload) => {
        if (isTrollboxLiveEvent(payload)) {
          listener(payload);
        }
      }, controller.signal)
      .catch((error: unknown) => {
        this.currentStatus = {
          ...this.baseStatus("error"),
          lastError: error instanceof Error ? error.message : "transport stream failed",
          note: `Backend canonical ${room} trollbox transport stream failed`,
        };
      })
      .finally(() => {
        this.activeStreams.delete(controller);
      });

    return async () => {
      controller.abort();
      this.activeStreams.delete(controller);
      if (this.activeStreams.size === 0) {
        await this.refreshStatus();
      }
    };
  }

  private async refreshStatus(): Promise<void> {
    try {
      const { data } = await this.techtree.transportStatus();
      this.currentStatus = {
        ...data,
        enabled: this.config.enabled,
        eventSocketPath: this.config.enabled ? this.eventSocketPath : null,
      };
    } catch (error) {
      this.currentStatus = {
        ...this.baseStatus("error"),
        lastError: error instanceof Error ? error.message : "unable to load backend transport status",
        note: "Backend transport status fetch failed",
      };
    }
  }

  private baseStatus(status: GossipsubStatus["status"]): GossipsubStatus {
    return {
      enabled: this.config.enabled,
      configured: this.config.enabled,
      connected: false,
      subscribedTopics: [],
      peerCount: 0,
      lastError: null,
      eventSocketPath: this.config.enabled ? this.eventSocketPath : null,
      status,
      note: this.config.enabled ? "Backend canonical trollbox transport configured" : "Trollbox transport disabled",
    };
  }
}
