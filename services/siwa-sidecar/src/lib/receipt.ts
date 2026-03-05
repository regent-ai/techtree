import { createHmac, randomUUID, timingSafeEqual } from "node:crypto";

import type { HexString, Result } from "../types.js";

type JsonObject = Record<string, unknown>;

interface ReceiptHeader {
  alg: "HS256";
  typ: "JWT";
}

export interface ReceiptClaims {
  typ: "siwa_receipt";
  jti: string;
  sub: HexString;
  aud: string;
  iat: number;
  exp: number;
  chainId: number;
  nonce: string;
  keyId: string;
  registryAddress?: HexString;
  tokenId?: string;
}

export interface IssueReceiptInput {
  walletAddress: HexString;
  chainId: number;
  nonce: string;
  keyId: string;
  nowUnixSeconds: number;
  ttlSeconds: number;
  audience: string;
  registryAddress?: HexString;
  tokenId?: string;
}

export interface IssuedReceipt {
  token: string;
  claims: ReceiptClaims;
}

export type VerifyReceiptError =
  | { kind: "invalid" }
  | { kind: "expired"; expiresAtUnixSeconds: number };

const isHexAddress = (value: unknown): value is HexString => {
  return typeof value === "string" && /^0x[a-fA-F0-9]{40}$/.test(value);
};

const isSafePositiveInteger = (value: unknown): value is number => {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
};

const isPositiveIntegerString = (value: unknown): value is string => {
  return typeof value === "string" && /^[1-9][0-9]*$/.test(value);
};

const base64UrlEncode = (input: Buffer | string): string => {
  return Buffer.from(input).toString("base64url");
};

const base64UrlDecode = (input: string): string => {
  return Buffer.from(input, "base64url").toString("utf8");
};

const signJws = (headerSegment: string, payloadSegment: string, secret: string): string => {
  const signingInput = `${headerSegment}.${payloadSegment}`;
  return createHmac("sha256", secret).update(signingInput, "utf8").digest("base64url");
};

const equalsSignature = (left: string, right: string): boolean => {
  const leftBuffer = Buffer.from(left, "utf8");
  const rightBuffer = Buffer.from(right, "utf8");

  if (leftBuffer.length !== rightBuffer.length) {
    return false;
  }

  return timingSafeEqual(leftBuffer, rightBuffer);
};

const parseHeader = (value: unknown): Result<ReceiptHeader, "invalid"> => {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return { ok: false, error: "invalid" };
  }

  const header = value as JsonObject;
  if (header.alg !== "HS256" || header.typ !== "JWT") {
    return { ok: false, error: "invalid" };
  }

  return {
    ok: true,
    value: {
      alg: "HS256",
      typ: "JWT",
    },
  };
};

const parseClaims = (value: unknown): Result<ReceiptClaims, "invalid"> => {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return { ok: false, error: "invalid" };
  }

  const claims = value as JsonObject;
  if (claims.typ !== "siwa_receipt") {
    return { ok: false, error: "invalid" };
  }

  if (typeof claims.jti !== "string" || claims.jti.length < 8) {
    return { ok: false, error: "invalid" };
  }

  if (!isHexAddress(claims.sub)) {
    return { ok: false, error: "invalid" };
  }

  if (typeof claims.aud !== "string" || claims.aud.trim() === "") {
    return { ok: false, error: "invalid" };
  }

  if (!isSafePositiveInteger(claims.iat) || !isSafePositiveInteger(claims.exp)) {
    return { ok: false, error: "invalid" };
  }

  if (claims.exp <= claims.iat) {
    return { ok: false, error: "invalid" };
  }

  if (!isSafePositiveInteger(claims.chainId)) {
    return { ok: false, error: "invalid" };
  }

  if (typeof claims.nonce !== "string" || claims.nonce.length < 8) {
    return { ok: false, error: "invalid" };
  }

  if (typeof claims.keyId !== "string" || claims.keyId.trim() === "") {
    return { ok: false, error: "invalid" };
  }

  if (claims.registryAddress !== undefined && !isHexAddress(claims.registryAddress)) {
    return { ok: false, error: "invalid" };
  }

  if (claims.tokenId !== undefined && !isPositiveIntegerString(claims.tokenId)) {
    return { ok: false, error: "invalid" };
  }

  return {
    ok: true,
    value: {
      typ: "siwa_receipt",
      jti: claims.jti,
      sub: claims.sub,
      aud: claims.aud,
      iat: claims.iat,
      exp: claims.exp,
      chainId: claims.chainId,
      nonce: claims.nonce,
      keyId: claims.keyId,
      ...(claims.registryAddress ? { registryAddress: claims.registryAddress } : {}),
      ...(claims.tokenId ? { tokenId: claims.tokenId } : {}),
    },
  };
};

export const issueReceiptToken = (input: IssueReceiptInput, secret: string): IssuedReceipt => {
  const claims: ReceiptClaims = {
    typ: "siwa_receipt",
    jti: randomUUID(),
    sub: input.walletAddress.toLowerCase() as HexString,
    aud: input.audience,
    iat: input.nowUnixSeconds,
    exp: input.nowUnixSeconds + input.ttlSeconds,
    chainId: input.chainId,
    nonce: input.nonce,
    keyId: input.keyId,
    ...(input.registryAddress ? { registryAddress: input.registryAddress } : {}),
    ...(input.tokenId ? { tokenId: input.tokenId } : {}),
  };

  const header: ReceiptHeader = {
    alg: "HS256",
    typ: "JWT",
  };

  const headerSegment = base64UrlEncode(JSON.stringify(header));
  const payloadSegment = base64UrlEncode(JSON.stringify(claims));
  const signatureSegment = signJws(headerSegment, payloadSegment, secret);

  return {
    token: `${headerSegment}.${payloadSegment}.${signatureSegment}`,
    claims,
  };
};

export const verifyReceiptToken = (
  token: string,
  secret: string,
  nowUnixSeconds: number,
): Result<ReceiptClaims, VerifyReceiptError> => {
  const segments = token.split(".");
  if (segments.length !== 3) {
    return { ok: false, error: { kind: "invalid" } };
  }

  const [headerSegment, payloadSegment, signatureSegment] = segments;
  if (!headerSegment || !payloadSegment || !signatureSegment) {
    return { ok: false, error: { kind: "invalid" } };
  }

  const expectedSignature = signJws(headerSegment, payloadSegment, secret);
  if (!equalsSignature(signatureSegment, expectedSignature)) {
    return { ok: false, error: { kind: "invalid" } };
  }

  let headerJson: unknown;
  let payloadJson: unknown;
  try {
    headerJson = JSON.parse(base64UrlDecode(headerSegment));
    payloadJson = JSON.parse(base64UrlDecode(payloadSegment));
  } catch {
    return { ok: false, error: { kind: "invalid" } };
  }

  const parsedHeader = parseHeader(headerJson);
  if (!parsedHeader.ok) {
    return { ok: false, error: { kind: "invalid" } };
  }

  const claims = parseClaims(payloadJson);
  if (!claims.ok) {
    return { ok: false, error: { kind: "invalid" } };
  }

  if (nowUnixSeconds > claims.value.exp) {
    return {
      ok: false,
      error: {
        kind: "expired",
        expiresAtUnixSeconds: claims.value.exp,
      },
    };
  }

  return { ok: true, value: claims.value };
};

export const parseAuthorizationReceipt = (authorizationValue: string): Result<string, "invalid"> => {
  const trimmed = authorizationValue.trim();
  const match = /^SIWA\s+(.+)$/.exec(trimmed);

  if (!match || !match[1]) {
    return { ok: false, error: "invalid" };
  }

  return {
    ok: true,
    value: match[1].trim(),
  };
};
