import type { XmtpStatus } from "./xmtp-status.js";

export interface LocalAgentIdentity {
  walletAddress: `0x${string}`;
  chainId: number;
  registryAddress: `0x${string}`;
  tokenId: string;
  label?: string;
}

export interface TransportStatus {
  enabled: boolean;
  status: "disabled" | "starting" | "ready" | "stopped" | "stub" | "error" | "degraded";
  mode?: "libp2p" | "local_only" | "degraded";
  ready?: boolean;
  configured?: boolean;
  connected?: boolean;
  subscribedTopics?: string[];
  peerCount?: number;
  lastError?: string | null;
  note?: string;
}

export interface HealthCheck {
  ok: boolean;
  baseUrl: string;
  latencyMs: number | null;
  payload?: Record<string, unknown>;
  error?: string;
}

export interface RuntimeStatus {
  running: boolean;
  socketPath: string;
  stateDir: string;
  logLevel: "debug" | "info" | "warn" | "error";
  authenticated: boolean;
  session: {
    walletAddress: `0x${string}`;
    chainId: number;
    receiptExpiresAt: string;
  } | null;
  agentIdentity: LocalAgentIdentity | null;
  techtree: HealthCheck | null;
  gossipsub: TransportStatus;
  xmtp: XmtpStatus;
}
