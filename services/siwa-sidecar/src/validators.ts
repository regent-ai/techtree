import type {
  AbsolutePath,
  HexString,
  HttpVerifyRequest,
  NonceRequest,
  Result,
  SiwaRequest,
  VerifyRequest,
} from "./types.js";

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === "object" && value !== null && !Array.isArray(value);
};

const isHexAddress = (value: unknown): value is HexString => {
  return typeof value === "string" && /^0x[a-fA-F0-9]{40}$/.test(value);
};

const isPositiveInt = (value: unknown): value is number => {
  return typeof value === "number" && Number.isInteger(value) && value > 0;
};

const normalizeHeaders = (headers: unknown): Result<Record<string, string>, string> => {
  if (!isRecord(headers)) {
    return { ok: false, error: "headers must be an object" };
  }

  const output: Record<string, string> = {};
  for (const [key, value] of Object.entries(headers)) {
    if (typeof value !== "string") {
      return {
        ok: false,
        error: `header '${key}' must be a string`,
      };
    }
    output[key] = value;
  }

  return { ok: true, value: output };
};

export const parseRequestBody = (rawBody: string): Result<SiwaRequest, string> => {
  let json: unknown;

  try {
    json = JSON.parse(rawBody);
  } catch {
    return { ok: false, error: "request body must be valid JSON" };
  }

  if (!isRecord(json) || typeof json.kind !== "string") {
    return {
      ok: false,
      error: "request body must include a discriminant 'kind' field",
    };
  }

  switch (json.kind) {
    case "nonce_request": {
      if (!isHexAddress(json.walletAddress)) {
        return { ok: false, error: "walletAddress must be a 0x-prefixed 20-byte hex address" };
      }
      if (!isPositiveInt(json.chainId)) {
        return { ok: false, error: "chainId must be a positive integer" };
      }
      if (json.audience !== undefined && typeof json.audience !== "string") {
        return { ok: false, error: "audience must be a string when provided" };
      }
      if (json.ttlSeconds !== undefined && !isPositiveInt(json.ttlSeconds)) {
        return { ok: false, error: "ttlSeconds must be a positive integer when provided" };
      }

      const valueBase: NonceRequest = {
        kind: "nonce_request",
        walletAddress: json.walletAddress,
        chainId: json.chainId,
      };
      const value: NonceRequest = {
        ...valueBase,
        ...(typeof json.audience === "string" ? { audience: json.audience } : {}),
        ...(typeof json.ttlSeconds === "number" ? { ttlSeconds: json.ttlSeconds } : {}),
      };
      return { ok: true, value };
    }

    case "verify_request": {
      if (!isHexAddress(json.walletAddress)) {
        return { ok: false, error: "walletAddress must be a 0x-prefixed 20-byte hex address" };
      }
      if (!isPositiveInt(json.chainId)) {
        return { ok: false, error: "chainId must be a positive integer" };
      }
      if (typeof json.nonce !== "string" || json.nonce.length < 8) {
        return { ok: false, error: "nonce must be a string with length >= 8" };
      }
      if (typeof json.message !== "string" || json.message.length < 8) {
        return { ok: false, error: "message must be a non-empty SIWA payload string" };
      }
      if (typeof json.signature !== "string" || !/^0x[a-fA-F0-9]+$/.test(json.signature)) {
        return { ok: false, error: "signature must be a 0x-prefixed hex string" };
      }
      if (json.registryAddress !== undefined && !isHexAddress(json.registryAddress)) {
        return { ok: false, error: "registryAddress must be a 0x-prefixed 20-byte hex address when provided" };
      }
      if (
        json.tokenId !== undefined &&
        (typeof json.tokenId !== "string" || !/^[1-9][0-9]*$/.test(json.tokenId))
      ) {
        return { ok: false, error: "tokenId must be a positive integer string when provided" };
      }
      if ((json.registryAddress === undefined) !== (json.tokenId === undefined)) {
        return {
          ok: false,
          error: "registryAddress and tokenId must be provided together when binding receipt to registry identity",
        };
      }

      const value: VerifyRequest = {
        kind: "verify_request",
        walletAddress: json.walletAddress,
        chainId: json.chainId,
        nonce: json.nonce,
        message: json.message,
        signature: json.signature as HexString,
        ...(typeof json.registryAddress === "string"
          ? { registryAddress: json.registryAddress }
          : {}),
        ...(typeof json.tokenId === "string" ? { tokenId: json.tokenId } : {}),
      };
      return { ok: true, value };
    }

    case "http_verify_request": {
      if (typeof json.method !== "string" || json.method.length === 0) {
        return { ok: false, error: "method is required" };
      }
      if (typeof json.path !== "string" || !json.path.startsWith("/")) {
        return { ok: false, error: "path must be an absolute path" };
      }
      const headersResult = normalizeHeaders(json.headers);
      if (!headersResult.ok) {
        return { ok: false, error: headersResult.error };
      }
      if (json.rawBody !== undefined && typeof json.rawBody !== "string") {
        return { ok: false, error: "rawBody must be a string when provided" };
      }
      if (json.raw_body !== undefined && typeof json.raw_body !== "string") {
        return { ok: false, error: "raw_body must be a string when provided" };
      }
      if (json.bodyDigest !== undefined && typeof json.bodyDigest !== "string") {
        return { ok: false, error: "bodyDigest must be a string when provided" };
      }

      const valueBase: HttpVerifyRequest = {
        kind: "http_verify_request",
        method: json.method.toUpperCase(),
        path: json.path as AbsolutePath,
        headers: headersResult.value,
      };
      const rawBody =
        typeof json.rawBody === "string"
          ? json.rawBody
          : typeof json.raw_body === "string"
            ? json.raw_body
            : undefined;
      const value: HttpVerifyRequest = {
        ...valueBase,
        ...(typeof rawBody === "string" ? { rawBody } : {}),
        ...(typeof json.bodyDigest === "string" ? { bodyDigest: json.bodyDigest } : {}),
      };

      return { ok: true, value };
    }

    default:
      return { ok: false, error: "unsupported request kind" };
  }
};
