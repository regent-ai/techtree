export type RegentXmtpEnv = "local" | "dev" | "production";

export interface RegentXmtpProfiles {
  owner: string;
  public: string;
  group: string;
}

export interface RegentXmtpConfig {
  enabled: boolean;
  env: RegentXmtpEnv;
  dbPath: string;
  dbEncryptionKeyPath: string;
  walletKeyPath: string;
  ownerInboxIds: string[];
  trustedInboxIds: string[];
  publicPolicyPath: string;
  profiles: RegentXmtpProfiles;
}

export interface XmtpClientInfo {
  address: `0x${string}`;
  inboxId: string;
  installationId: string;
  isRegistered: boolean;
  appVersion?: string;
  libxmtpVersion?: string;
}

export interface XmtpInitResult {
  configPath: string;
  enabled: boolean;
  env: RegentXmtpEnv;
  dbPath: string;
  dbEncryptionKeyPath: string;
  walletKeyPath: string;
  publicPolicyPath: string;
  ownerInboxIds: string[];
  trustedInboxIds: string[];
  profiles: RegentXmtpProfiles;
  createdWalletKey: boolean;
  createdDbEncryptionKey: boolean;
  createdPolicyFile: boolean;
  client: XmtpClientInfo | null;
}
