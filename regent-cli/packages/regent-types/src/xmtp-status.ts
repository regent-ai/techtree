import type { RegentXmtpEnv, RegentXmtpProfiles, XmtpClientInfo } from "./xmtp.js";

export interface XmtpStatus {
  enabled: boolean;
  status: "disabled" | "stopped" | "ready" | "stub" | "error" | "degraded";
  configured: boolean;
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
  client: XmtpClientInfo | null;
}
