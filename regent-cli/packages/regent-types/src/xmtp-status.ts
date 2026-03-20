import type {
  RegentXmtpEnv,
  RegentXmtpProfiles,
  XmtpClientInfo,
  XmtpRecentConversation,
  XmtpRecentError,
  XmtpRuntimeMetrics,
} from "./xmtp.js";

export interface XmtpStatus {
  enabled: boolean;
  status: "disabled" | "starting" | "stopped" | "ready" | "error" | "degraded";
  configured: boolean;
  connected: boolean;
  ready: boolean;
  started: boolean;
  env: RegentXmtpEnv;
  dbPath: string;
  walletKeyPath: string;
  dbEncryptionKeyPath: string;
  publicPolicyPath: string;
  ownerInboxIds: string[];
  trustedInboxIds: string[];
  profiles: RegentXmtpProfiles;
  note?: string;
  lastError?: string | null;
  recentErrors: XmtpRecentError[];
  recentConversations: XmtpRecentConversation[];
  metrics: XmtpRuntimeMetrics;
  routeState: "disabled" | "monitoring" | "blocked";
  client: XmtpClientInfo | null;
}
