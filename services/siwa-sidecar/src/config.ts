import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

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

const parsePositiveInt = (
  value: string | undefined,
  fallback: number,
): number => {
  if (!value) {
    return fallback;
  }
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }
  return parsed;
};

const sidecarDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(sidecarDir, "../../..");
const dotenvCandidates = [
  path.join(repoRoot, ".env"),
  path.join(repoRoot, ".env.local"),
];

const parseDotenvLine = (line: string): [string, string] | null => {
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith("#")) {
    return null;
  }

  const normalized = trimmed.startsWith("export ")
    ? trimmed.slice(7).trim()
    : trimmed;
  const equalsIndex = normalized.indexOf("=");
  if (equalsIndex <= 0) {
    return null;
  }

  const key = normalized.slice(0, equalsIndex).trim();
  if (!key) {
    return null;
  }

  let value = normalized.slice(equalsIndex + 1).trim();
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    value = value.slice(1, -1);
  }

  return [key, value];
};

const loadDotenvEnv = (): NodeJS.ProcessEnv => {
  const merged: NodeJS.ProcessEnv = { ...process.env };

  for (const candidate of dotenvCandidates) {
    if (!fs.existsSync(candidate)) {
      continue;
    }

    const raw = fs.readFileSync(candidate, "utf8");
    for (const line of raw.split(/\r?\n/)) {
      const parsed = parseDotenvLine(line);
      if (!parsed) {
        continue;
      }

      const [key, value] = parsed;
      if (merged[key] === undefined) {
        merged[key] = value;
      }
    }
  }

  return merged;
};

const DEV_ONLY_SECRET = "dev-only-change-me";

const isProductionEnv = (env: NodeJS.ProcessEnv): boolean => {
  return (env.NODE_ENV ?? "").toLowerCase() === "production";
};

const requireSecret = (
  env: NodeJS.ProcessEnv,
  key: string,
  fallback?: string,
): string => {
  const value = env[key] ?? fallback ?? "";

  if (typeof value !== "string" || value.trim() === "") {
    if (isProductionEnv(env)) {
      throw new Error(`Missing required SIWA secret: ${key}`);
    }

    return fallback ?? "";
  }

  if (isProductionEnv(env) && value === DEV_ONLY_SECRET) {
    throw new Error(
      `Refusing to boot SIWA sidecar with insecure default for ${key}`,
    );
  }

  return value;
};

export const loadConfig = (
  env: NodeJS.ProcessEnv = loadDotenvEnv(),
): SidecarConfig => {
  const hmacSecret = requireSecret(env, "SIWA_HMAC_SECRET", DEV_ONLY_SECRET);
  const receiptSecret = requireSecret(env, "SIWA_RECEIPT_SECRET", hmacSecret);

  return {
    port: parsePositiveInt(env.SIWA_PORT, 4100),
    nonceTtlSeconds: parsePositiveInt(env.SIWA_NONCE_TTL_SECONDS, 300),
    receiptTtlSeconds: parsePositiveInt(env.SIWA_RECEIPT_TTL_SECONDS, 900),
    hmacSecret,
    receiptSecret,
    hmacKeyId: env.SIWA_HMAC_KEY_ID ?? "sidecar-internal-v1",
    hmacMaxSkewSeconds: parsePositiveInt(env.SIWA_HMAC_MAX_SKEW_SECONDS, 300),
    httpSignatureMaxAgeSeconds: parsePositiveInt(
      env.SIWA_HTTP_MAX_AGE_SECONDS,
      300,
    ),
    httpSignatureCreatedDriftSeconds: parsePositiveInt(
      env.SIWA_HTTP_CREATED_DRIFT_SECONDS,
      5,
    ),
    httpReplayTtlSeconds: parsePositiveInt(
      env.SIWA_HTTP_REPLAY_TTL_SECONDS,
      300,
    ),
  };
};
