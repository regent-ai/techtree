import { createServer } from "node:http";
import { createHash, randomUUID } from "node:crypto";

import { loadConfig } from "./config.js";
import {
  buildHttpSignatureSigningMessage,
  contentDigestMatchesBody,
  requiredCoveredComponentsForHeaders,
  validateHttpSignatureEnvelope,
} from "./lib/http-signature.js";
import { verifyTrustedHmac } from "./lib/hmac.js";
import { InMemoryNonceStore } from "./lib/nonce-store.js";
import {
  issueReceiptToken,
  verifyReceiptToken,
} from "./lib/receipt.js";
import { InMemoryReplayStore } from "./lib/replay-store.js";
import { parseSiweMessage } from "./lib/siwe.js";
import { verifyPersonalSignMessage } from "./lib/evm-signature.js";
import { parseRequestBody } from "./validators.js";
import type {
  ApiFailure,
  ApiSuccess,
  EndpointErrorCodeMap,
  Endpoint,
  EndpointResponse,
  EndpointRequestMap,
  EndpointDataMap,
  ErrorDetails,
  HexString,
  IsoUtcString,
  Result,
  VerifyRequest,
} from "./types.js";

const config = loadConfig();
const nonceStore = new InMemoryNonceStore();
const replayStore = new InMemoryReplayStore();

const TRUSTED_ENDPOINTS: ReadonlySet<Endpoint> = new Set(["/v1/agent/siwa/http-verify"]);
const MAX_BODY_BYTES = 1_000_000;
const HTTP_VERIFY_REQUIRED_HEADERS = [
  "x-siwa-receipt",
  "signature",
  "signature-input",
  "x-key-id",
  "x-timestamp",
] as const;
const HTTP_SIGNATURE_INPUT_FORMAT =
  'sig1=("@method" "@path" "x-siwa-receipt" "x-key-id" ...);created=<unix>;expires=<unix>;nonce="<nonce>";keyid="<id>"';

const toIsoUtcString = (value: Date): IsoUtcString => {
  return value.toISOString() as IsoUtcString;
};

const isHexAddress = (value: string): value is HexString => {
  return /^0x[a-fA-F0-9]{40}$/.test(value);
};

const parsePositiveIntegerHeader = (value: string): number | null => {
  if (!/^[1-9][0-9]*$/.test(value)) {
    return null;
  }

  const parsed = Number.parseInt(value, 10);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    return null;
  }

  return parsed;
};

const readBody = async (req: NodeJS.ReadableStream): Promise<string> => {
  const chunks: Buffer[] = [];
  let size = 0;

  for await (const chunk of req) {
    const bufferChunk = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += bufferChunk.byteLength;

    if (size > MAX_BODY_BYTES) {
      throw new Error("request body exceeds max bytes");
    }

    chunks.push(bufferChunk);
  }

  return Buffer.concat(chunks).toString("utf8");
};

const buildSuccess = <E extends Endpoint>(
  endpoint: E,
  requestId: string,
  code: ApiSuccess<E>["code"],
  data: EndpointDataMap[E],
): ApiSuccess<E> => {
  return {
    ok: true,
    code,
    data,
    meta: {
      version: "v1",
      endpoint,
      requestId,
      timestamp: toIsoUtcString(new Date()),
    },
  };
};

const buildError = <E extends Endpoint, C extends EndpointErrorCodeMap[E]>(
  endpoint: E,
  requestId: string,
  code: C,
  message: string,
  details?: ErrorDetails<C>,
): ApiFailure<E> => {
  const errorPayload = details === undefined ? { message } : { message, details };

  return {
    ok: false,
    code,
    error: errorPayload,
    meta: {
      version: "v1",
      endpoint,
      requestId,
      timestamp: toIsoUtcString(new Date()),
    },
  } as ApiFailure<E>;
};

const statusFor = (response: EndpointResponse<Endpoint>): number => {
  if (response.ok) {
    return 200;
  }

  switch (response.code) {
    case "bad_request":
      return 400;
    case "auth_headers_missing":
    case "auth_key_id_invalid":
    case "auth_timestamp_invalid":
    case "auth_timestamp_out_of_window":
    case "auth_signature_mismatch":
    case "receipt_invalid":
    case "receipt_expired":
    case "receipt_binding_mismatch":
    case "http_signature_mismatch":
      return 401;
    case "request_replayed":
      return 409;
    case "nonce_not_found":
      return 404;
    case "nonce_expired":
    case "nonce_already_used":
    case "signature_invalid":
    case "http_headers_missing":
    case "http_signature_invalid":
    case "http_signature_input_invalid":
    case "http_required_components_missing":
      return 422;
    case "internal_error":
      return 500;
    default:
      return 500;
  }
};

type VerifySignedSiwaError =
  | { reason: "siwe_message_invalid"; message: string }
  | { reason: "siwe_address_mismatch"; message: string }
  | { reason: "siwe_nonce_mismatch"; message: string }
  | { reason: "siwe_chain_mismatch"; message: string }
  | { reason: "siwe_signature_mismatch"; message: string };

const verifySignedSiwaMessage = async (
  request: VerifyRequest,
): Promise<Result<true, VerifySignedSiwaError>> => {
  const parsedSiwe = parseSiweMessage(request.message);
  if (!parsedSiwe.ok) {
    return {
      ok: false,
      error: {
        reason: "siwe_message_invalid",
        message: parsedSiwe.error.message,
      },
    };
  }

  if (parsedSiwe.value.address.toLowerCase() !== request.walletAddress.toLowerCase()) {
    return {
      ok: false,
      error: {
        reason: "siwe_address_mismatch",
        message: "SIWE address must match walletAddress in verify request",
      },
    };
  }

  if (parsedSiwe.value.nonce !== request.nonce) {
    return {
      ok: false,
      error: {
        reason: "siwe_nonce_mismatch",
        message: "SIWE nonce must match nonce in verify request",
      },
    };
  }

  if (parsedSiwe.value.chainId !== request.chainId) {
    return {
      ok: false,
      error: {
        reason: "siwe_chain_mismatch",
        message: "SIWE Chain ID must match chainId in verify request",
      },
    };
  }

  const verification = await verifyPersonalSignMessage(
    request.message,
    request.signature,
    request.walletAddress,
  );

  if (!verification.ok) {
    if (verification.error === "cast_unavailable") {
      throw new Error("cast binary is required for SIWA signature verification");
    }
    return {
      ok: false,
      error: {
        reason: "siwe_signature_mismatch",
        message: "SIWE signature does not match walletAddress",
      },
    };
  }

  return { ok: true, value: true };
};

const parseReceiptFromHeaders = (
  headers: Record<string, string>,
): Result<{ token: string }, "invalid"> => {
  const siwaReceipt = headers["x-siwa-receipt"];
  if (typeof siwaReceipt !== "string" || siwaReceipt.trim() === "") {
    return { ok: false, error: "invalid" };
  }

  return {
    ok: true,
    value: {
      token: siwaReceipt.trim(),
    },
  };
};

const handlers: {
  [E in Endpoint]: (
    input: EndpointRequestMap[E],
    requestId: string,
  ) => Promise<EndpointResponse<E>>;
} = {
  "/v1/agent/siwa/nonce": async (input, requestId) => {
    const issueInputBase = {
      walletAddress: input.walletAddress,
      chainId: input.chainId,
      ttlSeconds: input.ttlSeconds ?? config.nonceTtlSeconds,
    };
    const issueInput = {
      ...issueInputBase,
      ...(typeof input.audience === "string" ? { audience: input.audience } : {}),
    };

    const issued = await nonceStore.issue(issueInput);

    return buildSuccess("/v1/agent/siwa/nonce", requestId, "nonce_issued", {
      nonce: issued.nonce,
      walletAddress: issued.walletAddress,
      chainId: issued.chainId,
      expiresAt: toIsoUtcString(new Date(issued.expiresAtMs)),
    });
  },

  "/v1/agent/siwa/verify": async (input, requestId) => {
    const signatureValidation = await verifySignedSiwaMessage(input);
    if (!signatureValidation.ok) {
      return buildError("/v1/agent/siwa/verify", requestId, "signature_invalid", signatureValidation.error.message);
    }

    const nonceResult = await nonceStore.consume({
      walletAddress: input.walletAddress,
      nonce: input.nonce,
      chainId: input.chainId,
    });

    if (!nonceResult.ok) {
      if (nonceResult.error.kind === "not_found") {
        return buildError("/v1/agent/siwa/verify", requestId, "nonce_not_found", "nonce not found");
      }
      if (nonceResult.error.kind === "chain_mismatch") {
        return buildError(
          "/v1/agent/siwa/verify",
          requestId,
          "signature_invalid",
          "SIWA nonce is not valid for the requested chainId",
        );
      }
      if (nonceResult.error.kind === "expired") {
        return buildError("/v1/agent/siwa/verify", requestId, "nonce_expired", "nonce expired", {
          expiresAt: toIsoUtcString(new Date(nonceResult.error.expiresAtMs)),
        });
      }
      return buildError("/v1/agent/siwa/verify", requestId, "nonce_already_used", "nonce already used", {
        consumedAt: toIsoUtcString(new Date(nonceResult.error.consumedAtMs)),
      });
    }

    const keyId = input.walletAddress.toLowerCase();
    const nowUnixSeconds = Math.floor(Date.now() / 1000);
    const receipt = issueReceiptToken(
      {
        walletAddress: input.walletAddress,
        chainId: input.chainId,
        nonce: input.nonce,
        keyId,
        nowUnixSeconds,
        ttlSeconds: config.receiptTtlSeconds,
        audience: nonceResult.value.audience ?? "techtree",
        ...(typeof input.registryAddress === "string"
          ? { registryAddress: input.registryAddress }
          : {}),
        ...(typeof input.tokenId === "string" ? { tokenId: input.tokenId } : {}),
      },
      config.receiptSecret,
    );

    return buildSuccess("/v1/agent/siwa/verify", requestId, "siwa_verified", {
      verified: true,
      walletAddress: input.walletAddress,
      chainId: input.chainId,
      nonce: input.nonce,
      keyId,
      signatureScheme: "evm_personal_sign",
      receipt: receipt.token,
      receiptExpiresAt: toIsoUtcString(new Date(receipt.claims.exp * 1000)),
    });
  },

  "/v1/agent/siwa/http-verify": async (input, requestId) => {
    const envelopeCheck = validateHttpSignatureEnvelope(input.headers);
    if (!envelopeCheck.ok) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        envelopeCheck.code,
        envelopeCheck.message,
        envelopeCheck.details,
      );
    }

    const envelope = envelopeCheck.envelope;
    const nowUnixSeconds = Math.floor(Date.now() / 1000);

    const parsedReceipt = parseReceiptFromHeaders(envelope.normalizedHeaders);
    if (!parsedReceipt.ok) {
      return buildError("/v1/agent/siwa/http-verify", requestId, "receipt_invalid", "invalid SIWA receipt token", {
        expectedFormat: "x-siwa-receipt: <receipt-token>",
      });
    }

    const verifiedReceipt = verifyReceiptToken(parsedReceipt.value.token, config.receiptSecret, nowUnixSeconds);
    if (!verifiedReceipt.ok) {
      if (verifiedReceipt.error.kind === "expired") {
        return buildError(
          "/v1/agent/siwa/http-verify",
          requestId,
          "receipt_expired",
          "SIWA receipt is expired",
          {
            expiresAt: toIsoUtcString(new Date(verifiedReceipt.error.expiresAtUnixSeconds * 1000)),
          },
        );
      }

      return buildError("/v1/agent/siwa/http-verify", requestId, "receipt_invalid", "invalid SIWA receipt token", {
        expectedFormat: "x-siwa-receipt: <receipt-token>",
      });
    }

    const receiptClaims = verifiedReceipt.value;
    const expectedKeyIdFromWallet = receiptClaims.sub.toLowerCase();
    if (receiptClaims.keyId !== expectedKeyIdFromWallet) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "receipt_binding_mismatch",
        "receipt keyId is not bound to receipt walletAddress",
        {
          binding: "x-key-id",
          expected: expectedKeyIdFromWallet,
          received: receiptClaims.keyId,
        },
      );
    }

    const keyIdHeader = envelope.normalizedHeaders["x-key-id"];
    if (typeof keyIdHeader !== "string") {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "receipt_binding_mismatch",
        "x-key-id does not match SIWA receipt",
        {
          binding: "x-key-id",
          expected: receiptClaims.keyId,
          received: "",
        },
      );
    }

    if (keyIdHeader !== receiptClaims.keyId) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "receipt_binding_mismatch",
        "x-key-id does not match SIWA receipt",
        {
          binding: "x-key-id",
          expected: receiptClaims.keyId,
          received: keyIdHeader,
        },
      );
    }

    if (
      typeof envelope.parsedSignatureInput.keyId === "string" &&
      envelope.parsedSignatureInput.keyId !== receiptClaims.keyId
    ) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "receipt_binding_mismatch",
        "signature-input keyid does not match SIWA receipt keyId",
        {
          binding: "x-key-id",
          expected: receiptClaims.keyId,
          received: envelope.parsedSignatureInput.keyId,
        },
      );
    }

    const walletHeaderRaw = envelope.normalizedHeaders["x-agent-wallet-address"];
    if (typeof walletHeaderRaw !== "string") {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "receipt_binding_mismatch",
        "x-agent-wallet-address does not match SIWA receipt",
        {
          binding: "x-agent-wallet-address",
          expected: receiptClaims.sub,
          received: "",
        },
      );
    }

    const walletHeader = walletHeaderRaw.trim();
    if (!isHexAddress(walletHeader)) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "receipt_binding_mismatch",
        "x-agent-wallet-address must be a 0x-prefixed 20-byte hex address",
        {
          binding: "x-agent-wallet-address",
          expected: receiptClaims.sub,
          received: walletHeader,
        },
      );
    }

    if (walletHeader.toLowerCase() !== receiptClaims.sub.toLowerCase()) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "receipt_binding_mismatch",
        "x-agent-wallet-address does not match SIWA receipt",
        {
          binding: "x-agent-wallet-address",
          expected: receiptClaims.sub,
          received: walletHeader,
        },
      );
    }

    const chainIdHeaderRaw = envelope.normalizedHeaders["x-agent-chain-id"];
    if (typeof chainIdHeaderRaw !== "string") {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "receipt_binding_mismatch",
        "x-agent-chain-id does not match SIWA receipt",
        {
          binding: "x-agent-chain-id",
          expected: String(receiptClaims.chainId),
          received: "",
        },
      );
    }

    const chainIdHeader = chainIdHeaderRaw.trim();
    const parsedChainId = parsePositiveIntegerHeader(chainIdHeader);
    if (parsedChainId === null) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "receipt_binding_mismatch",
        "x-agent-chain-id must be a positive integer",
        {
          binding: "x-agent-chain-id",
          expected: String(receiptClaims.chainId),
          received: chainIdHeader,
        },
      );
    }

    if (parsedChainId !== receiptClaims.chainId) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "receipt_binding_mismatch",
        "x-agent-chain-id does not match SIWA receipt",
        {
          binding: "x-agent-chain-id",
          expected: String(receiptClaims.chainId),
          received: chainIdHeader,
        },
      );
    }

    const timestampHeader = envelope.normalizedHeaders["x-timestamp"];
    if (typeof timestampHeader !== "string") {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "http_signature_input_invalid",
        "x-timestamp must be a positive unix timestamp",
        {
          expectedFormat: HTTP_SIGNATURE_INPUT_FORMAT,
        },
      );
    }

    const timestampSeconds = parsePositiveIntegerHeader(timestampHeader);
    if (timestampSeconds === null) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "http_signature_input_invalid",
        "x-timestamp must be a positive unix timestamp",
        {
          expectedFormat: HTTP_SIGNATURE_INPUT_FORMAT,
        },
      );
    }

    if (Math.abs(nowUnixSeconds - timestampSeconds) > config.httpSignatureMaxAgeSeconds) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "http_signature_input_invalid",
        "x-timestamp is outside allowed freshness window",
        {
          expectedFormat: HTTP_SIGNATURE_INPUT_FORMAT,
        },
      );
    }

    if (
      Math.abs(timestampSeconds - envelope.parsedSignatureInput.createdUnixSeconds) >
      config.httpSignatureCreatedDriftSeconds
    ) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "http_signature_input_invalid",
        "signature-input created value drift exceeds allowed tolerance",
        {
          expectedFormat: HTTP_SIGNATURE_INPUT_FORMAT,
        },
      );
    }

    if (envelope.parsedSignatureInput.expiresUnixSeconds <= nowUnixSeconds) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "http_signature_input_invalid",
        "signature-input has expired",
        {
          expectedFormat: HTTP_SIGNATURE_INPUT_FORMAT,
        },
      );
    }

    const registryHeaderRaw = envelope.normalizedHeaders["x-agent-registry-address"];
    if (typeof registryHeaderRaw !== "string") {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "receipt_binding_mismatch",
        "x-agent-registry-address does not match SIWA receipt",
        {
          binding: "x-agent-registry-address",
          expected: receiptClaims.registryAddress ?? "",
          received: "",
        },
      );
    }

    if (!receiptClaims.registryAddress) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "receipt_binding_mismatch",
        "SIWA receipt missing registry address binding",
        {
          binding: "x-agent-registry-address",
          expected: registryHeaderRaw,
          received: "",
        },
      );
    }

    const registryHeader = registryHeaderRaw.trim();
    if (!isHexAddress(registryHeader)) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "receipt_binding_mismatch",
        "x-agent-registry-address must be a 0x-prefixed 20-byte hex address",
        {
          binding: "x-agent-registry-address",
          expected: receiptClaims.registryAddress,
          received: registryHeader,
        },
      );
    }

    if (registryHeader.toLowerCase() !== receiptClaims.registryAddress.toLowerCase()) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "receipt_binding_mismatch",
        "x-agent-registry-address does not match SIWA receipt",
        {
          binding: "x-agent-registry-address",
          expected: receiptClaims.registryAddress,
          received: registryHeader,
        },
      );
    }

    const tokenIdHeaderRaw = envelope.normalizedHeaders["x-agent-token-id"];
    if (typeof tokenIdHeaderRaw !== "string") {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "receipt_binding_mismatch",
        "x-agent-token-id does not match SIWA receipt",
        {
          binding: "x-agent-token-id",
          expected: receiptClaims.tokenId ?? "",
          received: "",
        },
      );
    }

    if (!receiptClaims.tokenId) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "receipt_binding_mismatch",
        "SIWA receipt missing token id binding",
        {
          binding: "x-agent-token-id",
          expected: tokenIdHeaderRaw,
          received: "",
        },
      );
    }

    const tokenIdHeader = tokenIdHeaderRaw.trim();
    const parsedTokenId = parsePositiveIntegerHeader(tokenIdHeader);
    if (parsedTokenId === null) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "receipt_binding_mismatch",
        "x-agent-token-id must be a positive integer",
        {
          binding: "x-agent-token-id",
          expected: receiptClaims.tokenId,
          received: tokenIdHeader,
        },
      );
    }

    if (tokenIdHeader !== receiptClaims.tokenId) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "receipt_binding_mismatch",
        "x-agent-token-id does not match SIWA receipt",
        {
          binding: "x-agent-token-id",
          expected: receiptClaims.tokenId,
          received: tokenIdHeader,
        },
      );
    }

    if (typeof input.body === "string" && Buffer.byteLength(input.body) > 0) {
      const contentDigest = envelope.normalizedHeaders["content-digest"];

      if (typeof contentDigest !== "string" || contentDigest.trim() === "") {
        return buildError(
          "/v1/agent/siwa/http-verify",
          requestId,
          "http_signature_input_invalid",
          "content-digest is required for signed requests with a body",
          {
            expectedFormat: HTTP_SIGNATURE_INPUT_FORMAT,
          },
        );
      }

      if (!contentDigestMatchesBody(input.body, contentDigest)) {
        return buildError(
          "/v1/agent/siwa/http-verify",
          requestId,
          "http_signature_input_invalid",
          "content-digest does not match request body",
          {
            expectedFormat: HTTP_SIGNATURE_INPUT_FORMAT,
          },
        );
      }
    }

    const signingMessage = buildHttpSignatureSigningMessage(input.method, input.path, envelope);
    if (!signingMessage.ok) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "http_signature_input_invalid",
        "signature-input references components missing from headers",
        {
          expectedFormat: HTTP_SIGNATURE_INPUT_FORMAT,
        },
      );
    }

    const replayKey = createHash("sha256")
      .update(
        `${receiptClaims.keyId}|${envelope.parsedSignatureInput.nonce}|${input.method}|${input.path}`,
      )
      .digest("hex");

    const signatureVerified = await verifyPersonalSignMessage(
      signingMessage.value,
      envelope.signatureHex,
      receiptClaims.sub,
    );

    if (!signatureVerified.ok) {
      if (signatureVerified.error === "cast_unavailable") {
        throw new Error("cast binary is required for HTTP signature verification");
      }

      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "http_signature_mismatch",
        "http signature does not match SIWA receipt wallet",
        {
          expectedWalletAddress: receiptClaims.sub,
        },
      );
    }

    const replayClaimed = replayStore.claim(replayKey, config.httpReplayTtlSeconds * 1000);
    if (!replayClaimed) {
      return buildError(
        "/v1/agent/siwa/http-verify",
        requestId,
        "request_replayed",
        "request signature has already been used",
        { replayKey },
      );
    }

    const requiredCoveredComponents = requiredCoveredComponentsForHeaders(envelope.normalizedHeaders);

    return buildSuccess("/v1/agent/siwa/http-verify", requestId, "http_envelope_valid", {
      verified: true,
      walletAddress: receiptClaims.sub,
      chainId: receiptClaims.chainId,
      keyId: receiptClaims.keyId,
      receiptExpiresAt: toIsoUtcString(new Date(receiptClaims.exp * 1000)),
      requiredHeaders: HTTP_VERIFY_REQUIRED_HEADERS,
      requiredCoveredComponents,
      coveredComponents: envelope.coveredComponents,
    });
  },
};

const endpointFromPath = (path: string): Endpoint | null => {
  if (path === "/v1/agent/siwa/nonce" || path === "/v1/agent/siwa/verify" || path === "/v1/agent/siwa/http-verify") {
    return path;
  }
  return null;
};

const server = createServer(async (req, res) => {
  const requestId = randomUUID();
  const path = req.url?.split("?")[0] ?? "";
  const endpoint = endpointFromPath(path);

  if (!endpoint) {
    res.writeHead(404, { "content-type": "application/json" });
    res.end(
      JSON.stringify(
        buildError("/v1/agent/siwa/nonce", requestId, "bad_request", "unknown endpoint, use /v1/* paths"),
      ),
    );
    return;
  }

  if (req.method !== "POST") {
    const response = buildError(endpoint, requestId, "bad_request", "only POST is supported");
    res.writeHead(405, {
      "content-type": "application/json",
      allow: "POST",
    });
    res.end(JSON.stringify(response));
    return;
  }

  let body = "";
  try {
    body = await readBody(req);
  } catch (error) {
    const response = buildError(
      endpoint,
      requestId,
      "bad_request",
      error instanceof Error ? error.message : "unable to read request body",
    );
    res.writeHead(400, { "content-type": "application/json" });
    res.end(JSON.stringify(response));
    return;
  }

  if (TRUSTED_ENDPOINTS.has(endpoint)) {
    const auth = verifyTrustedHmac(
      {
        method: req.method,
        path: endpoint,
        body: body,
        headers: req.headers,
      },
      {
        secret: config.hmacSecret,
        keyId: config.hmacKeyId,
        maxSkewSeconds: config.hmacMaxSkewSeconds,
      },
    );

    if (!auth.ok) {
      const response = buildError(endpoint, requestId, auth.code, auth.message, auth.details);
      res.writeHead(statusFor(response), { "content-type": "application/json" });
      res.end(JSON.stringify(response));
      return;
    }
  }

  const parseResult = parseRequestBody(body);
  if (!parseResult.ok) {
    const response = buildError(endpoint, requestId, "bad_request", parseResult.error);
    res.writeHead(400, { "content-type": "application/json" });
    res.end(JSON.stringify(response));
    return;
  }

  const parsed = parseResult.value;

  const expectedKindByEndpoint: Record<Endpoint, string> = {
    "/v1/agent/siwa/nonce": "nonce_request",
    "/v1/agent/siwa/verify": "verify_request",
    "/v1/agent/siwa/http-verify": "http_verify_request",
  };

  if (parsed.kind !== expectedKindByEndpoint[endpoint]) {
    const response = buildError(
      endpoint,
      requestId,
      "bad_request",
      `payload kind '${parsed.kind}' does not match endpoint '${endpoint}'`,
    );
    res.writeHead(400, { "content-type": "application/json" });
    res.end(JSON.stringify(response));
    return;
  }

  try {
    let response: EndpointResponse<Endpoint>;

    if (endpoint === "/v1/agent/siwa/nonce" && parsed.kind === "nonce_request") {
      response = await handlers["/v1/agent/siwa/nonce"](parsed, requestId);
    } else if (endpoint === "/v1/agent/siwa/verify" && parsed.kind === "verify_request") {
      response = await handlers["/v1/agent/siwa/verify"](parsed, requestId);
    } else if (endpoint === "/v1/agent/siwa/http-verify" && parsed.kind === "http_verify_request") {
      response = await handlers["/v1/agent/siwa/http-verify"](parsed, requestId);
    } else {
      const mismatch = buildError(
        endpoint,
        requestId,
        "bad_request",
        `payload kind '${parsed.kind}' does not match endpoint '${endpoint}'`,
      );
      res.writeHead(400, { "content-type": "application/json" });
      res.end(JSON.stringify(mismatch));
      return;
    }

    res.writeHead(statusFor(response), {
      "content-type": "application/json",
    });
    res.end(JSON.stringify(response));
  } catch (error) {
    const response = buildError(
      endpoint,
      requestId,
      "internal_error",
      error instanceof Error ? error.message : "internal server error",
    );
    res.writeHead(500, { "content-type": "application/json" });
    res.end(JSON.stringify(response));
  }
});

server.listen(config.port, () => {
  console.log(`siwa-sidecar listening on http://localhost:${config.port}`);
});
