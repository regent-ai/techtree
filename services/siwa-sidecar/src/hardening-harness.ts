import {
  buildHttpSignatureSigningMessage,
  validateHttpSignatureEnvelope,
} from "./lib/http-signature.js";
import { loadConfig } from "./config.js";
import {
  deriveAddressFromPrivateKey,
  signPersonalMessageWithPrivateKey,
  verifyPersonalSignMessage,
} from "./lib/evm-signature.js";
import {
  issueReceiptToken,
  verifyReceiptToken,
} from "./lib/receipt.js";
import { parseSiweMessage } from "./lib/siwe.js";
import { InMemoryReplayStore } from "./lib/replay-store.js";
import type { HexString, Result } from "./types.js";

const assert = (condition: boolean, message: string): void => {
  if (!condition) {
    throw new Error(message);
  }
};

const mustOk = <T, E>(result: Result<T, E>, message: string): T => {
  if (!result.ok) {
    throw new Error(`${message}: ${String(result.error)}`);
  }

  return result.value;
};

const toSig1Signature = (signatureHex: HexString): string => {
  return `sig1=:${Buffer.from(signatureHex.slice(2), "hex").toString("base64")}:`;
};

const privateKey =
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" as HexString;

const main = async (): Promise<void> => {
  let missingSecretRejected = false;

  try {
    loadConfig({ SIWA_RECEIPT_SECRET: "receipt-only" });
  } catch {
    missingSecretRejected = true;
  }

  assert(missingSecretRejected, "sidecar config must reject missing SIWA_HMAC_SECRET");

  const walletAddress = mustOk(
    await deriveAddressFromPrivateKey(privateKey),
    "unable to derive address from private key",
  );

  const nonce = "12345678deadbeef";
  const nowUnixSeconds = Math.floor(Date.now() / 1000);
  const keyId = walletAddress.toLowerCase();
  const registryAddress = "0x000000000000000000000000000000000000beef" as HexString;
  const tokenId = "42";

  const domain = "regent.cx";
  const uri = "https://regent.cx/login";
  const issuedAt = new Date(nowUnixSeconds * 1000).toISOString();
  const message = [
    `${domain} wants you to sign in with your Ethereum account:`,
    walletAddress,
    "",
    "Sign in to Regent SIWA sidecar.",
    "",
    `URI: ${uri}`,
    "Version: 1",
    "Chain ID: 84532",
    `Nonce: ${nonce}`,
    `Issued At: ${issuedAt}`,
  ].join("\n");

  const parsedSiwe = parseSiweMessage(message);
  assert(parsedSiwe.ok, "valid SIWE message should parse");

  const messageSignature = mustOk(
    await signPersonalMessageWithPrivateKey(privateKey, message),
    "unable to sign SIWA message",
  );

  const verifiedMessage = await verifyPersonalSignMessage(message, messageSignature, walletAddress);
  assert(verifiedMessage.ok, "personal_sign SIWA verification failed");

  const receipt = issueReceiptToken(
    {
      walletAddress,
      chainId: 84532,
      nonce,
      keyId,
      nowUnixSeconds,
      ttlSeconds: 300,
      audience: "techtree",
      registryAddress,
      tokenId,
    },
    "test-receipt-secret",
  );

  const verifiedReceipt = verifyReceiptToken(receipt.token, "test-receipt-secret", nowUnixSeconds);
  assert(verifiedReceipt.ok, "receipt verification failed");
  if (verifiedReceipt.ok) {
    assert(verifiedReceipt.value.sub === walletAddress.toLowerCase(), "receipt subject wallet mismatch");
    assert(verifiedReceipt.value.registryAddress === registryAddress, "receipt registry binding mismatch");
    assert(verifiedReceipt.value.tokenId === tokenId, "receipt token binding mismatch");
  }

  const expiredReceipt = verifyReceiptToken(receipt.token, "test-receipt-secret", nowUnixSeconds + 301);
  assert(!expiredReceipt.ok && expiredReceipt.error.kind === "expired", "receipt should expire deterministically");

  const method = "POST";
  const path = "/v1/agent/nodes";
  const signatureExpires = nowUnixSeconds + 120;
  const signatureNonce = `nonce-${nowUnixSeconds}`;
  const signatureInputCanonical =
    `("@method" "@path" "x-siwa-receipt" "x-key-id" "x-timestamp" ` +
    `"x-agent-wallet-address" "x-agent-chain-id" "x-agent-registry-address" "x-agent-token-id")` +
    `;created=${nowUnixSeconds};expires=${signatureExpires};nonce="${signatureNonce}";keyid="${keyId}"`;

  const placeholderHeaders = {
    "x-siwa-receipt": receipt.token,
    signature: "sig1=:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=:",
    "signature-input": `sig1=${signatureInputCanonical}`,
    "x-key-id": keyId,
    "x-timestamp": String(nowUnixSeconds),
    "x-agent-wallet-address": walletAddress,
    "x-agent-chain-id": "84532",
    "x-agent-registry-address": registryAddress,
    "x-agent-token-id": tokenId,
  };

  const parsedEnvelope = validateHttpSignatureEnvelope(placeholderHeaders);
  if (!parsedEnvelope.ok) {
    throw new Error(`http envelope parsing failed: ${parsedEnvelope.code}`);
  }

  const signingMessage = mustOk(
    buildHttpSignatureSigningMessage(method, path, parsedEnvelope.envelope),
    "unable to build HTTP signing message",
  );

  const httpSignatureHex = mustOk(
    await signPersonalMessageWithPrivateKey(privateKey, signingMessage),
    "unable to sign HTTP signature message",
  );

  const finalHeadersHex = {
    ...placeholderHeaders,
    signature: toSig1Signature(httpSignatureHex),
  };

  const envelopeHex = validateHttpSignatureEnvelope(finalHeadersHex);
  assert(envelopeHex.ok, "http envelope rejected canonical sig1 signature format");

  const replayStore = new InMemoryReplayStore();
  const replayKey = `${keyId}|${signatureNonce}|${method}|${path}`;
  assert(replayStore.claim(replayKey, 30_000) === true, "first replay claim should succeed");
  assert(replayStore.claim(replayKey, 30_000) === false, "second replay claim should be rejected");

  const missingProtectedComponentHeaders = {
    ...placeholderHeaders,
    "signature-input":
      `sig1=("@method" "@path" "x-siwa-receipt" "x-key-id" "x-agent-wallet-address" ` +
      `"x-agent-chain-id" "x-agent-registry-address" "x-agent-token-id")` +
      `;created=${nowUnixSeconds};expires=${signatureExpires};nonce="${signatureNonce}";keyid="${keyId}"`,
  };

  const missingProtectedResult = validateHttpSignatureEnvelope(missingProtectedComponentHeaders);
  assert(
    !missingProtectedResult.ok && missingProtectedResult.code === "http_required_components_missing",
    "http signature-input missing x-timestamp must fail",
  );

  const verifiedHttpSignature = await verifyPersonalSignMessage(
    signingMessage,
    httpSignatureHex,
    walletAddress,
  );
  assert(verifiedHttpSignature.ok, "http signature cryptographic verification failed");

  console.log("siwa-sidecar hardening harness passed");
};

await main();
