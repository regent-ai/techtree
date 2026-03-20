import type { RegentXmtpConfig } from "./xmtp.js";

export type RegentLogLevel = "debug" | "info" | "warn" | "error";

export interface RegentRuntimeConfig {
  socketPath: string;
  stateDir: string;
  logLevel: RegentLogLevel;
}

export interface RegentTechtreeConfig {
  baseUrl: string;
  audience: string;
  defaultChainId: number;
  requestTimeoutMs: number;
}

export interface RegentWalletConfig {
  privateKeyEnv: string;
  keystorePath: string;
}

export interface RegentGossipsubConfig {
  enabled: boolean;
  listenAddrs: string[];
  bootstrap: string[];
  peerIdPath: string;
}

export interface RegentConfig {
  runtime: RegentRuntimeConfig;
  techtree: RegentTechtreeConfig;
  wallet: RegentWalletConfig;
  gossipsub: RegentGossipsubConfig;
  xmtp: RegentXmtpConfig;
}
