export interface SidecarConfig {
  port: number;
  nonceTtlSeconds: number;
  receiptTtlSeconds: number;
  hmacSecret: string;
  receiptSecret: string;
  hmacKeyId: string;
  hmacMaxSkewSeconds: number;
  httpSignatureMaxAgeSeconds: number;
  httpSignatureCreatedDriftSeconds: number;
  httpReplayTtlSeconds: number;
}

const parsePositiveInt = (value: string | undefined, fallback: number): number => {
  if (!value) {
    return fallback;
  }
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }
  return parsed;
};

export const loadConfig = (env: NodeJS.ProcessEnv = process.env): SidecarConfig => {
  const hmacSecret = env.SIWA_HMAC_SECRET ?? "dev-only-change-me";

  return {
    port: parsePositiveInt(env.SIWA_PORT, 4100),
    nonceTtlSeconds: parsePositiveInt(env.SIWA_NONCE_TTL_SECONDS, 300),
    receiptTtlSeconds: parsePositiveInt(env.SIWA_RECEIPT_TTL_SECONDS, 900),
    hmacSecret,
    receiptSecret: env.SIWA_RECEIPT_SECRET ?? hmacSecret,
    hmacKeyId: env.SIWA_HMAC_KEY_ID ?? "sidecar-internal-v1",
    hmacMaxSkewSeconds: parsePositiveInt(env.SIWA_HMAC_MAX_SKEW_SECONDS, 300),
    httpSignatureMaxAgeSeconds: parsePositiveInt(env.SIWA_HTTP_MAX_AGE_SECONDS, 300),
    httpSignatureCreatedDriftSeconds: parsePositiveInt(env.SIWA_HTTP_CREATED_DRIFT_SECONDS, 5),
    httpReplayTtlSeconds: parsePositiveInt(env.SIWA_HTTP_REPLAY_TTL_SECONDS, 300),
  };
};
