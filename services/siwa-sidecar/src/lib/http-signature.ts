import type {
  AbsolutePath,
  ErrorDetails,
  HexString,
  HttpEnvelopeErrorCode,
  HttpMethod,
  Result,
} from "../types.js";

export interface ParsedSignatureInput {
  components: readonly string[];
  createdUnixSeconds: number;
  expiresUnixSeconds: number;
  nonce: string;
  keyId: string | null;
  signatureParams: string;
}

export interface HttpSignatureEnvelope {
  normalizedHeaders: Record<string, string>;
  signatureHex: HexString;
  parsedSignatureInput: ParsedSignatureInput;
  coveredComponents: readonly string[];
}

export type HttpEnvelopeFailure<C extends HttpEnvelopeErrorCode> = {
  ok: false;
  code: C;
  message: string;
} & (ErrorDetails<C> extends never ? {} : { details: ErrorDetails<C> });

export type HttpEnvelopeCheck =
  | {
      ok: true;
      envelope: HttpSignatureEnvelope;
    }
  | {
      [C in HttpEnvelopeErrorCode]: HttpEnvelopeFailure<C>;
    }[HttpEnvelopeErrorCode];

const REQUIRED_HEADERS = ["signature", "signature-input", "x-key-id", "x-timestamp"] as const;
const REQUIRED_BASE_COMPONENTS = ["@method", "@path", "x-key-id", "x-timestamp"] as const;
const RECEIPT_HEADERS = ["x-siwa-receipt", "authorization"] as const;

const COMPONENT_VALUE = /^"([^\s"]+)"$/;
const HEADER_COMPONENT = /^[a-z0-9-]+$/;
const HEX_SIGNATURE = /^0x[0-9a-fA-F]+$/;
const SIG1_SIGNATURE = /^sig1=:([A-Za-z0-9+/=]+):$/;
const BASE64_SIGNATURE = /^[A-Za-z0-9+/]+={0,2}$/;

const toLowerHeaderMap = (headers: Record<string, string>): Record<string, string> => {
  const normalized: Record<string, string> = {};
  for (const [name, value] of Object.entries(headers)) {
    normalized[name.toLowerCase()] = value;
  }
  return normalized;
};

const bytesToHexSignature = (bytes: Buffer): Result<HexString, "invalid"> => {
  if (bytes.length !== 65) {
    return { ok: false, error: "invalid" };
  }

  return {
    ok: true,
    value: `0x${bytes.toString("hex")}` as HexString,
  };
};

const toHexSignature = (signatureValue: string): Result<HexString, "invalid"> => {
  const trimmed = signatureValue.trim();
  if (HEX_SIGNATURE.test(trimmed)) {
    const rawHex = trimmed.slice(2);
    const bytes = Buffer.from(rawHex, "hex");
    return bytesToHexSignature(bytes);
  }

  const sig1Match = SIG1_SIGNATURE.exec(trimmed);
  if (sig1Match?.[1]) {
    const signatureBytes = Buffer.from(sig1Match[1], "base64");
    return bytesToHexSignature(signatureBytes);
  }

  if (BASE64_SIGNATURE.test(trimmed)) {
    const signatureBytes = Buffer.from(trimmed, "base64");
    return bytesToHexSignature(signatureBytes);
  }

  return { ok: false, error: "invalid" };
};

interface ParsedSignatureInputRaw {
  componentsRaw: string;
  paramsRaw: string;
}

const parseSignatureInputRaw = (signatureInput: string): Result<ParsedSignatureInputRaw, "invalid"> => {
  const trimmed = signatureInput.trim();

  const equalsIndex = trimmed.indexOf("=(");
  if (equalsIndex > 0) {
    const afterEquals = trimmed.slice(equalsIndex + 1);
    if (!afterEquals.startsWith("(")) {
      return { ok: false, error: "invalid" };
    }
    const closeIndex = afterEquals.indexOf(")");
    if (closeIndex < 0) {
      return { ok: false, error: "invalid" };
    }

    const componentsRaw = afterEquals.slice(1, closeIndex).trim();
    const paramsRaw = afterEquals.slice(closeIndex + 1).trim();
    return { ok: true, value: { componentsRaw, paramsRaw } };
  }

  if (!trimmed.startsWith("(")) {
    return { ok: false, error: "invalid" };
  }

  const closeIndex = trimmed.indexOf(")");
  if (closeIndex < 0) {
    return { ok: false, error: "invalid" };
  }

  const componentsRaw = trimmed.slice(1, closeIndex).trim();
  const paramsRaw = trimmed.slice(closeIndex + 1).trim();
  return { ok: true, value: { componentsRaw, paramsRaw } };
};

const parseSignatureInput = (signatureInput: string): Result<ParsedSignatureInput, "invalid"> => {
  const parsedRaw = parseSignatureInputRaw(signatureInput);
  if (!parsedRaw.ok) {
    return { ok: false, error: "invalid" };
  }

  const componentTokens = parsedRaw.value.componentsRaw.split(/\s+/).filter((token) => token.length > 0);
  if (componentTokens.length === 0) {
    return { ok: false, error: "invalid" };
  }

  const components: string[] = [];
  for (const token of componentTokens) {
    const tokenMatch = COMPONENT_VALUE.exec(token);
    const component = tokenMatch?.[1];

    if (!component) {
      return { ok: false, error: "invalid" };
    }

    if (component === "@method" || component === "@path") {
      components.push(component);
      continue;
    }

    if (component.startsWith("@") || !HEADER_COMPONENT.test(component.toLowerCase())) {
      return { ok: false, error: "invalid" };
    }

    components.push(component.toLowerCase());
  }

  const unique = new Set(components);
  if (unique.size !== components.length) {
    return { ok: false, error: "invalid" };
  }

  const params = parsedRaw.value.paramsRaw
    .split(";")
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);

  let createdUnixSeconds: number | null = null;
  let expiresUnixSeconds: number | null = null;
  let nonce: string | null = null;
  let keyId: string | null = null;

  for (const param of params) {
    const createdMatch = /^created=(\d+)$/.exec(param);
    if (createdMatch?.[1]) {
      const created = Number.parseInt(createdMatch[1], 10);
      if (!Number.isSafeInteger(created) || created <= 0) {
        return { ok: false, error: "invalid" };
      }
      createdUnixSeconds = created;
      continue;
    }

    const keyIdMatch = /^keyid="([^"]+)"$/.exec(param);
    if (keyIdMatch?.[1]) {
      keyId = keyIdMatch[1];
      continue;
    }

    const expiresMatch = /^expires=(\d+)$/.exec(param);
    if (expiresMatch?.[1]) {
      const expires = Number.parseInt(expiresMatch[1], 10);
      if (!Number.isSafeInteger(expires) || expires <= 0) {
        return { ok: false, error: "invalid" };
      }
      expiresUnixSeconds = expires;
      continue;
    }

    const nonceMatch = /^nonce="([^"]+)"$/.exec(param);
    if (nonceMatch?.[1]) {
      const parsedNonce = nonceMatch[1].trim();
      if (parsedNonce.length < 8 || parsedNonce.length > 128) {
        return { ok: false, error: "invalid" };
      }
      nonce = parsedNonce;
      continue;
    }
  }

  if (createdUnixSeconds === null || expiresUnixSeconds === null || nonce === null) {
    return { ok: false, error: "invalid" };
  }

  if (expiresUnixSeconds <= createdUnixSeconds) {
    return { ok: false, error: "invalid" };
  }

  const signatureParams =
    `(${components.map((component) => `"${component}"`).join(" ")})` +
    `;created=${createdUnixSeconds}` +
    `;expires=${expiresUnixSeconds}` +
    `;nonce="${nonce}"` +
    (keyId ? `;keyid="${keyId}"` : "");

  return {
    ok: true,
    value: {
      components,
      createdUnixSeconds,
      expiresUnixSeconds,
      nonce,
      keyId,
      signatureParams,
    },
  };
};

export const requiredCoveredComponentsForHeaders = (
  normalizedHeaders: Record<string, string>,
): readonly string[] => {
  const required: string[] = [...REQUIRED_BASE_COMPONENTS];

  if (typeof normalizedHeaders["x-siwa-receipt"] === "string") {
    required.push("x-siwa-receipt");
  } else if (typeof normalizedHeaders.authorization === "string") {
    required.push("authorization");
  }

  if (typeof normalizedHeaders["x-agent-wallet-address"] === "string") {
    required.push("x-agent-wallet-address");
  }

  if (typeof normalizedHeaders["x-agent-chain-id"] === "string") {
    required.push("x-agent-chain-id");
  }

  if (typeof normalizedHeaders["x-agent-registry-address"] === "string") {
    required.push("x-agent-registry-address");
  }

  if (typeof normalizedHeaders["x-agent-token-id"] === "string") {
    required.push("x-agent-token-id");
  }

  return required;
};

const hasReceiptHeader = (normalized: Record<string, string>): boolean => {
  return RECEIPT_HEADERS.some((header) => typeof normalized[header] === "string");
};

export const validateHttpSignatureEnvelope = (
  headers: Record<string, string>,
): HttpEnvelopeCheck => {
  const normalized = toLowerHeaderMap(headers);
  const missing: string[] = REQUIRED_HEADERS.filter((name) => !normalized[name]);

  if (!hasReceiptHeader(normalized)) {
    missing.push("x-siwa-receipt|authorization");
  }

  if (missing.length > 0) {
    return {
      ok: false,
      code: "http_headers_missing",
      message: "missing required HTTP signature headers",
      details: {
        requiredHeaders: [...REQUIRED_HEADERS, "x-siwa-receipt|authorization"],
        missing,
      },
    };
  }

  const signature = normalized.signature;
  const signatureInput = normalized["signature-input"];

  if (!signature) {
    return {
      ok: false,
      code: "http_signature_invalid",
      message: "invalid signature header format",
      details: { expectedFormat: "0x<hex-signature> | sig1=:base64(signature): | <base64(signature)>" },
    };
  }

  const signatureHex = toHexSignature(signature);
  if (!signatureHex.ok) {
    return {
      ok: false,
      code: "http_signature_invalid",
      message: "invalid signature header format",
      details: { expectedFormat: "0x<hex-signature> | sig1=:base64(signature): | <base64(signature)>" },
    };
  }

  if (!signatureInput) {
    return {
      ok: false,
      code: "http_signature_input_invalid",
      message: "invalid signature-input header format",
      details: {
        expectedFormat:
          'sig1=("@method" "@path" "x-siwa-receipt" "x-key-id" ...);created=<unix>;expires=<unix>;nonce="<nonce>";keyid="<id>"',
      },
    };
  }

  const parsedInput = parseSignatureInput(signatureInput);
  if (!parsedInput.ok) {
    return {
      ok: false,
      code: "http_signature_input_invalid",
      message: "invalid signature-input header format",
      details: {
        expectedFormat:
          'sig1=("@method" "@path" "x-siwa-receipt" "x-key-id" ...);created=<unix>;expires=<unix>;nonce="<nonce>";keyid="<id>"',
      },
    };
  }

  const keyIdHeader = normalized["x-key-id"];
  if (parsedInput.value.keyId && keyIdHeader !== parsedInput.value.keyId) {
    return {
      ok: false,
      code: "http_signature_input_invalid",
      message: "signature-input keyid must match x-key-id header",
      details: {
        expectedFormat:
          'sig1=("@method" "@path" "x-siwa-receipt" "x-key-id" ...);created=<unix>;expires=<unix>;nonce="<nonce>";keyid="<id>"',
      },
    };
  }

  const requiredComponents = requiredCoveredComponentsForHeaders(normalized);
  const missingComponents = requiredComponents.filter(
    (required) => !parsedInput.value.components.includes(required),
  );

  if (missingComponents.length > 0) {
    return {
      ok: false,
      code: "http_required_components_missing",
      message: "signature-input missing required covered components",
      details: {
        requiredComponents,
        coveredComponents: parsedInput.value.components,
        missing: missingComponents,
      },
    };
  }

  return {
    ok: true,
    envelope: {
      normalizedHeaders: normalized,
      signatureHex: signatureHex.value,
      parsedSignatureInput: parsedInput.value,
      coveredComponents: parsedInput.value.components,
    },
  };
};

const normalizeHeaderValue = (value: string): string => {
  return value.replace(/[\t ]+/g, " ").trim();
};

const componentValue = (
  component: string,
  method: HttpMethod,
  path: AbsolutePath,
  normalizedHeaders: Record<string, string>,
): Result<string, "missing"> => {
  if (component === "@method") {
    return { ok: true, value: method.toLowerCase() };
  }

  if (component === "@path") {
    return { ok: true, value: path };
  }

  const headerValue = normalizedHeaders[component];
  if (typeof headerValue !== "string") {
    return { ok: false, error: "missing" };
  }

  return {
    ok: true,
    value: normalizeHeaderValue(headerValue),
  };
};

export const buildHttpSignatureSigningMessage = (
  method: HttpMethod,
  path: AbsolutePath,
  envelope: HttpSignatureEnvelope,
): Result<string, "component_missing"> => {
  const lines: string[] = [];

  for (const component of envelope.parsedSignatureInput.components) {
    const value = componentValue(component, method, path, envelope.normalizedHeaders);
    if (!value.ok) {
      return { ok: false, error: "component_missing" };
    }

    lines.push(`"${component}": ${value.value}`);
  }

  lines.push(`"@signature-params": ${envelope.parsedSignatureInput.signatureParams}`);

  return {
    ok: true,
    value: lines.join("\n"),
  };
};
