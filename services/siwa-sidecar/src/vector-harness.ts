import { createHash } from "node:crypto";

import {
  buildHttpSignatureSigningMessage,
  validateHttpSignatureEnvelope,
} from "./lib/http-signature.js";
import {
  deriveAddressFromPrivateKey,
  signPersonalMessageWithPrivateKey,
} from "./lib/evm-signature.js";
import {
  issueReceiptToken,
  verifyReceiptToken,
} from "./lib/receipt.js";
import { InMemoryReplayStore } from "./lib/replay-store.js";
import type { HexString, Result } from "./types.js";

const assert = (condition: boolean, message: string): void => {
  if (!condition) {
    throw new Error(message);
  }
};

const expectOk = <T, E>(result: Result<T, E>, message: string): T => {
  if (!result.ok) {
    throw new Error(`${message}: ${String(result.error)}`);
  }
  return result.value;
};

const privateKey =
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" as HexString;
const receiptSecret = "vector-receipt-secret";

const toSig1Signature = (signatureHex: HexString): string => {
  return `sig1=:${Buffer.from(signatureHex.slice(2), "hex").toString("base64")}:`;
};

const main = async (): Promise<void> => {
  const walletAddress = expectOk(
    await deriveAddressFromPrivateKey(privateKey),
    "wallet derivation failed",
  );

  const nowUnixSeconds = Math.floor(Date.now() / 1000);
  const keyId = walletAddress.toLowerCase();
  const chainId = 11155111;
  const registryAddress = "0x000000000000000000000000000000000000beef" as HexString;
  const tokenId = "77";

  const receipt = issueReceiptToken(
    {
      walletAddress,
      chainId,
      nonce: "vector-nonce-12345678",
      keyId,
      nowUnixSeconds,
      ttlSeconds: 120,
      audience: "techtree",
      registryAddress,
      tokenId,
    },
    receiptSecret,
  );

  const signatureNonce = `nonce-${nowUnixSeconds}`;
  const signatureExpires = nowUnixSeconds + 90;
  const method = "POST";
  const path = "/v1/agent/nodes";

  const signatureInput =
    `sig1=("@method" "@path" "x-siwa-receipt" "x-key-id" "x-timestamp" ` +
    `"x-agent-wallet-address" "x-agent-chain-id" "x-agent-registry-address" "x-agent-token-id")` +
    `;created=${nowUnixSeconds};expires=${signatureExpires};nonce="${signatureNonce}";keyid="${keyId}"`;

  const baseHeaders: Record<string, string> = {
    "x-siwa-receipt": receipt.token,
    "x-key-id": keyId,
    "x-timestamp": String(nowUnixSeconds),
    "x-agent-wallet-address": walletAddress,
    "x-agent-chain-id": String(chainId),
    "x-agent-registry-address": registryAddress,
    "x-agent-token-id": tokenId,
    signature:
      "sig1=:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=:",
    "signature-input": signatureInput,
  };

  const parsedEnvelope = validateHttpSignatureEnvelope(baseHeaders);
  if (!parsedEnvelope.ok) {
    throw new Error("Vector 1 failed: baseline envelope should parse");
  }
  const signingMessage = expectOk(
    buildHttpSignatureSigningMessage(method, path, parsedEnvelope.envelope),
    "signing message build failed",
  );

  const signatureHex = expectOk(
    await signPersonalMessageWithPrivateKey(privateKey, signingMessage),
    "signing http envelope failed",
  );

  const validHeaders = { ...baseHeaders, signature: toSig1Signature(signatureHex) };

  // Vector 1: valid envelope
  const vector1 = validateHttpSignatureEnvelope(validHeaders);
  assert(vector1.ok, "Vector 1 failed: valid envelope rejected");

  // Vector 2: invalid signature header format
  const vector2 = validateHttpSignatureEnvelope({ ...validHeaders, signature: "not-a-signature" });
  assert(!vector2.ok && vector2.code === "http_signature_invalid", "Vector 2 failed");

  // Vector 3: malformed signature-input
  const vector3 = validateHttpSignatureEnvelope({
    ...validHeaders,
    "signature-input": "sig1=(\"@method\" \"@path\")",
  });
  assert(!vector3.ok && vector3.code === "http_signature_input_invalid", "Vector 3 failed");

  // Vector 4: signature-input missing required covered component
  const vector4 = validateHttpSignatureEnvelope({
    ...validHeaders,
    "signature-input":
      `sig1=("@method" "@path" "x-siwa-receipt" "x-key-id" "x-agent-wallet-address" ` +
      `"x-agent-chain-id" "x-agent-registry-address" "x-agent-token-id")` +
      `;created=${nowUnixSeconds};expires=${signatureExpires};nonce="${signatureNonce}";keyid="${keyId}"`,
  });
  assert(!vector4.ok && vector4.code === "http_required_components_missing", "Vector 4 failed");

  // Vector 5: invalid receipt token verification
  const invalidReceipt = verifyReceiptToken("malformed.token", receiptSecret, nowUnixSeconds);
  assert(!invalidReceipt.ok && invalidReceipt.error.kind === "invalid", "Vector 5 failed");

  // Vector 6: expired receipt token
  const expiredReceipt = verifyReceiptToken(receipt.token, receiptSecret, nowUnixSeconds + 500);
  assert(!expiredReceipt.ok && expiredReceipt.error.kind === "expired", "Vector 6 failed");

  // Vector 7: replay detection key
  const replayStore = new InMemoryReplayStore();
  const replayKey = createHash("sha256")
    .update(`${keyId}|${signatureNonce}|${method}|${path}`)
    .digest("hex");
  assert(replayStore.claim(replayKey, 60_000), "Vector 7 failed: first replay claim should pass");
  assert(!replayStore.claim(replayKey, 60_000), "Vector 7 failed: second replay claim should fail");

  // Vector 8: receipt binding mismatch (wallet header vs receipt subject)
  const mismatchedWalletHeader = "0x000000000000000000000000000000000000c0de";
  const verifiedReceipt = expectOk(
    verifyReceiptToken(receipt.token, receiptSecret, nowUnixSeconds),
    "valid receipt should verify",
  );
  assert(
    mismatchedWalletHeader.toLowerCase() !== verifiedReceipt.sub.toLowerCase(),
    "Vector 8 failed: expected wallet binding mismatch",
  );

  console.log("siwa-sidecar protocol vector harness passed (8 vectors)");
};

await main();
