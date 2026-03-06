import type { WorkerConfig } from "./types.js";

const parseNumber = (value: string | undefined, fallback: number): number => {
  if (!value) return fallback;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? Math.trunc(parsed) : fallback;
};

const parseBoolean = (value: string | undefined, fallback: boolean): boolean => {
  if (value === undefined) {
    return fallback;
  }

  const normalized = value.trim().toLowerCase();
  if (normalized === "1" || normalized === "true" || normalized === "yes" || normalized === "on") {
    return true;
  }
  if (normalized === "0" || normalized === "false" || normalized === "no" || normalized === "off") {
    return false;
  }
  return fallback;
};

const parseXmtpEnv = (value: string | undefined): "dev" | "production" => {
  const normalized = value?.trim().toLowerCase();
  if (normalized === "production" || normalized === "prod") {
    return "production";
  }
  return "dev";
};

const parseTransportMode = (value: string | undefined): WorkerConfig["transportMode"] => {
  switch (value) {
    case "real":
      return "real";
    case "mock":
      return "mock";
    case undefined:
    case "":
    case "auto":
      return "auto";
    default:
      return "auto";
  }
};

export const loadConfig = (): WorkerConfig => {
  const phoenixInternalUrl =
    process.env.PHOENIX_INTERNAL_URL || "http://localhost:4000/api/internal";
  const xmtpWalletPrivateKey = process.env.XMTP_WALLET_PRIVATE_KEY || null;
  const xmtpDbEncryptionKey = process.env.XMTP_DB_ENCRYPTION_KEY || null;

  const canonicalRoomKey = process.env.XMTP_CANONICAL_ROOM_KEY || "public-trollbox";

  return {
    pollIntervalMs: parseNumber(process.env.XMTP_POLL_INTERVAL_MS, 5_000),
    requestTimeoutMs: parseNumber(process.env.XMTP_REQUEST_TIMEOUT_MS, 10_000),
    transportMode: parseTransportMode(process.env.XMTP_TRANSPORT_MODE),
    realTransportModule: process.env.XMTP_REAL_TRANSPORT_MODULE || null,
    xmtpEnv: parseXmtpEnv(process.env.XMTP_ENV),
    xmtpSdkModule: process.env.XMTP_SDK_MODULE || "@xmtp/node-sdk",
    xmtpEthersModule: process.env.XMTP_ETHERS_MODULE || "ethers",
    xmtpDbEncryptionKey,
    xmtpWalletPrivateKey,
    xmtpConsentProofEndpoint: process.env.XMTP_CONSENT_PROOF_ENDPOINT || null,
    xmtpRequireConsent: parseBoolean(process.env.XMTP_REQUIRE_CONSENT, false),
    xmtpCreateGroupIfMissing: parseBoolean(process.env.XMTP_CREATE_GROUP_IF_MISSING, true),
    mockMessageEveryHeartbeats: parseNumber(
      process.env.XMTP_MOCK_MESSAGE_EVERY_HEARTBEATS,
      0,
    ),
    membershipLeaseBatchSize: parseNumber(
      process.env.XMTP_MEMBERSHIP_LEASE_BATCH_SIZE,
      5,
    ),
    membershipCommandCacheTtlMs: parseNumber(
      process.env.XMTP_MEMBERSHIP_COMMAND_CACHE_TTL_MS,
      10 * 60 * 1_000,
    ),
    canonicalRoomKey,
    canonicalRoomName: process.env.XMTP_CANONICAL_ROOM_NAME || "Tech Tree Trollbox",
    canonicalRoomGroupId: process.env.XMTP_CANONICAL_ROOM_GROUP_ID || `xmtp-${canonicalRoomKey}`,
    internalSharedSecret: process.env.INTERNAL_SHARED_SECRET || "",
    roomEnsureEndpoint:
      process.env.XMTP_ROOM_ENSURE_ENDPOINT ||
      `${phoenixInternalUrl}/xmtp/rooms/ensure`,
    shardListEndpoint:
      process.env.XMTP_SHARD_LIST_ENDPOINT ||
      `${phoenixInternalUrl}/xmtp/shards`,
    messageIngestEndpoint:
      process.env.XMTP_MESSAGE_INGEST_ENDPOINT ||
      `${phoenixInternalUrl}/xmtp/messages/ingest`,
    leaseMembershipEndpoint:
      process.env.XMTP_LEASE_MEMBERSHIP_ENDPOINT ||
      `${phoenixInternalUrl}/xmtp/commands/lease`,
    resolveMembershipEndpointTemplate:
      process.env.XMTP_RESOLVE_MEMBERSHIP_ENDPOINT_TEMPLATE ||
      `${phoenixInternalUrl}/xmtp/commands/:id/resolve`,
  };
};
