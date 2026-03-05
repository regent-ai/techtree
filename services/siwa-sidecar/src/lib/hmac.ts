import { createHmac, timingSafeEqual } from "node:crypto";
import type { IncomingHttpHeaders } from "node:http";
import type { AuthErrorCode, ErrorDetails } from "../types.js";

export interface TrustedHmacContext {
  method: string;
  path: string;
  body: string;
  headers: IncomingHttpHeaders;
}

export interface TrustedHmacConfig {
  secret: string;
  keyId: string;
  maxSkewSeconds: number;
}

export type HmacAuthFailure<C extends AuthErrorCode> = {
  ok: false;
  code: C;
  message: string;
} & (ErrorDetails<C> extends never ? {} : { details: ErrorDetails<C> });

export type HmacAuthResult =
  | { ok: true }
  | {
      [C in AuthErrorCode]: HmacAuthFailure<C>;
    }[AuthErrorCode];

const KEY_ID_HEADER = "x-sidecar-key-id";
const TIMESTAMP_HEADER = "x-sidecar-timestamp";
const SIGNATURE_HEADER = "x-sidecar-signature";
const REQUIRED_HMAC_HEADERS = [KEY_ID_HEADER, TIMESTAMP_HEADER, SIGNATURE_HEADER] as const;

const readHeader = (headers: IncomingHttpHeaders, name: string): string | null => {
  const value = headers[name];
  if (Array.isArray(value)) {
    return value[0] ?? null;
  }
  return value ?? null;
};

const buildPayload = (ctx: TrustedHmacContext, unixSeconds: string): string => {
  return `${ctx.method.toUpperCase()}\n${ctx.path}\n${unixSeconds}\n${ctx.body}`;
};

const computeHexHmac = (secret: string, payload: string): string => {
  return createHmac("sha256", secret).update(payload, "utf8").digest("hex");
};

const equalsConstantTime = (left: string, right: string): boolean => {
  const leftBuf = Buffer.from(left, "utf8");
  const rightBuf = Buffer.from(right, "utf8");
  if (leftBuf.length !== rightBuf.length) {
    return false;
  }
  return timingSafeEqual(leftBuf, rightBuf);
};

export const verifyTrustedHmac = (
  ctx: TrustedHmacContext,
  config: TrustedHmacConfig,
): HmacAuthResult => {
  const keyId = readHeader(ctx.headers, KEY_ID_HEADER);
  const timestamp = readHeader(ctx.headers, TIMESTAMP_HEADER);
  const signature = readHeader(ctx.headers, SIGNATURE_HEADER);

  const missing = [
    ...(keyId ? [] : [KEY_ID_HEADER]),
    ...(timestamp ? [] : [TIMESTAMP_HEADER]),
    ...(signature ? [] : [SIGNATURE_HEADER]),
  ];
  if (missing.length > 0) {
    return {
      ok: false,
      code: "auth_headers_missing",
      message: "missing trusted-call authentication headers",
      details: {
        requiredHeaders: REQUIRED_HMAC_HEADERS,
        missing,
      },
    };
  }

  if (!keyId || !timestamp || !signature) {
    return {
      ok: false,
      code: "auth_headers_missing",
      message: "missing trusted-call authentication headers",
      details: {
        requiredHeaders: REQUIRED_HMAC_HEADERS,
        missing: REQUIRED_HMAC_HEADERS,
      },
    };
  }

  if (keyId !== config.keyId) {
    return {
      ok: false,
      code: "auth_key_id_invalid",
      message: "invalid trusted-call key id",
      details: {
        expectedKeyId: config.keyId,
        receivedKeyId: keyId,
      },
    };
  }

  const ts = Number.parseInt(timestamp, 10);
  if (!Number.isFinite(ts)) {
    return {
      ok: false,
      code: "auth_timestamp_invalid",
      message: "invalid timestamp header",
      details: {
        receivedTimestamp: timestamp,
      },
    };
  }

  const nowSeconds = Math.floor(Date.now() / 1000);
  if (Math.abs(nowSeconds - ts) > config.maxSkewSeconds) {
    return {
      ok: false,
      code: "auth_timestamp_out_of_window",
      message: "timestamp outside allowed skew",
      details: {
        nowUnixSeconds: nowSeconds,
        receivedUnixSeconds: ts,
        maxSkewSeconds: config.maxSkewSeconds,
      },
    };
  }

  const canonicalPayload = buildPayload(ctx, timestamp);
  const expected = `sha256=${computeHexHmac(config.secret, canonicalPayload)}`;

  if (!equalsConstantTime(signature, expected)) {
    return {
      ok: false,
      code: "auth_signature_mismatch",
      message: "hmac signature mismatch",
      details: {
        algorithm: "sha256",
      },
    };
  }

  return { ok: true };
};
