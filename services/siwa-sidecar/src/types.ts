export type HexString = `0x${string}`;
export type IsoUtcString = `${number}-${number}-${number}T${string}Z`;
export type AbsolutePath = `/${string}`;

export type Strict<T> = T & Record<Exclude<string, keyof T>, never>;
export type DeepReadonly<T> = T extends (...args: never[]) => unknown
  ? T
  : T extends object
    ? { readonly [K in keyof T]: DeepReadonly<T[K]> }
    : T;
export type Result<Ok, Err> = { ok: true; value: Ok } | { ok: false; error: Err };

export type Endpoint = "/v1/agent/siwa/nonce" | "/v1/agent/siwa/verify" | "/v1/agent/siwa/http-verify";
export type ApiVersion = "v1";

export interface ResponseMeta<E extends Endpoint> {
  version: ApiVersion;
  endpoint: E;
  requestId: string;
  timestamp: IsoUtcString;
}

export type SuccessCode = "nonce_issued" | "siwa_verified" | "http_envelope_valid";
export type SharedErrorCode = "bad_request" | "internal_error";
export type VerifyErrorCode =
  | "bad_request"
  | "internal_error"
  | "nonce_not_found"
  | "nonce_expired"
  | "nonce_already_used"
  | "signature_invalid";
export type AuthErrorCode =
  | "auth_headers_missing"
  | "auth_key_id_invalid"
  | "auth_timestamp_invalid"
  | "auth_timestamp_out_of_window"
  | "auth_signature_mismatch";
export type ReceiptErrorCode = "receipt_invalid" | "receipt_expired" | "receipt_binding_mismatch";
export type HttpEnvelopeErrorCode =
  | "http_headers_missing"
  | "http_signature_invalid"
  | "http_signature_input_invalid"
  | "http_required_components_missing"
  | "http_signature_mismatch"
  | "request_replayed";

export type EndpointErrorCodeMap = {
  "/v1/agent/siwa/nonce": SharedErrorCode;
  "/v1/agent/siwa/verify": VerifyErrorCode;
  "/v1/agent/siwa/http-verify": SharedErrorCode | AuthErrorCode | ReceiptErrorCode | HttpEnvelopeErrorCode;
};

export type ErrorCode =
  | EndpointErrorCodeMap["/v1/agent/siwa/nonce"]
  | EndpointErrorCodeMap["/v1/agent/siwa/verify"]
  | EndpointErrorCodeMap["/v1/agent/siwa/http-verify"];

export interface ErrorDetailsByCode {
  nonce_expired: {
    expiresAt: IsoUtcString;
  };
  nonce_already_used: {
    consumedAt: IsoUtcString;
  };
  auth_headers_missing: {
    requiredHeaders: readonly ["x-sidecar-key-id", "x-sidecar-timestamp", "x-sidecar-signature"];
    missing: readonly string[];
  };
  auth_key_id_invalid: {
    expectedKeyId: string;
    receivedKeyId: string;
  };
  auth_timestamp_invalid: {
    receivedTimestamp: string;
  };
  auth_timestamp_out_of_window: {
    nowUnixSeconds: number;
    receivedUnixSeconds: number;
    maxSkewSeconds: number;
  };
  auth_signature_mismatch: {
    algorithm: "sha256";
  };
  receipt_invalid: {
    expectedFormat: string;
  };
  receipt_expired: {
    expiresAt: IsoUtcString;
  };
  receipt_binding_mismatch: {
    binding:
      | "x-key-id"
      | "x-agent-wallet-address"
      | "x-agent-chain-id"
      | "x-agent-registry-address"
      | "x-agent-token-id";
    expected: string;
    received: string;
  };
  http_headers_missing: {
    requiredHeaders: readonly string[];
    missing: readonly string[];
  };
  http_signature_invalid: {
    expectedFormat: "sig1=:base64(signature):";
  };
  http_signature_input_invalid: {
    expectedFormat:
      'sig1=("@method" "@path" "x-siwa-receipt" "x-key-id" ...);created=<unix>;expires=<unix>;nonce="<nonce>";keyid="<id>"';
  };
  http_required_components_missing: {
    requiredComponents: readonly string[];
    coveredComponents: readonly string[];
    missing: readonly string[];
  };
  http_signature_mismatch: {
    expectedWalletAddress: HexString;
  };
  request_replayed: {
    replayKey: string;
  };
}

export type ErrorDetails<C extends ErrorCode> = C extends keyof ErrorDetailsByCode
  ? ErrorDetailsByCode[C]
  : never;

export type ApiErrorPayload<C extends ErrorCode> = {
  message: string;
} & (ErrorDetails<C> extends never ? {} : { details?: ErrorDetails<C> });

export type HttpMethod =
  | "GET"
  | "POST"
  | "PUT"
  | "PATCH"
  | "DELETE"
  | "HEAD"
  | "OPTIONS"
  | (string & {});

export interface NonceRequest {
  kind: "nonce_request";
  walletAddress: HexString;
  chainId: number;
  audience?: string;
  ttlSeconds?: number;
}

export interface VerifyRequest {
  kind: "verify_request";
  walletAddress: HexString;
  chainId: number;
  nonce: string;
  message: string;
  signature: HexString;
  registryAddress?: HexString;
  tokenId?: string;
}

export interface HttpVerifyRequest {
  kind: "http_verify_request";
  method: HttpMethod;
  path: AbsolutePath;
  headers: Record<string, string>;
  body?: string;
}

export type SiwaRequest = NonceRequest | VerifyRequest | HttpVerifyRequest;

export interface NonceIssued {
  nonce: string;
  walletAddress: HexString;
  chainId: number;
  expiresAt: IsoUtcString;
}

export interface SiwaVerified {
  verified: true;
  walletAddress: HexString;
  chainId: number;
  nonce: string;
  keyId: string;
  signatureScheme: "evm_personal_sign";
  receipt: string;
  receiptExpiresAt: IsoUtcString;
}

export interface HttpEnvelopeVerified {
  verified: true;
  walletAddress: HexString;
  chainId: number;
  keyId: string;
  receiptExpiresAt: IsoUtcString;
  requiredHeaders: readonly string[];
  requiredCoveredComponents: readonly string[];
  coveredComponents: readonly string[];
}

export type EndpointRequestMap = {
  "/v1/agent/siwa/nonce": NonceRequest;
  "/v1/agent/siwa/verify": VerifyRequest;
  "/v1/agent/siwa/http-verify": HttpVerifyRequest;
};

export type EndpointDataMap = {
  "/v1/agent/siwa/nonce": NonceIssued;
  "/v1/agent/siwa/verify": SiwaVerified;
  "/v1/agent/siwa/http-verify": HttpEnvelopeVerified;
};

export type EndpointSuccessCodeMap = {
  "/v1/agent/siwa/nonce": "nonce_issued";
  "/v1/agent/siwa/verify": "siwa_verified";
  "/v1/agent/siwa/http-verify": "http_envelope_valid";
};

export interface ApiSuccess<E extends Endpoint> {
  ok: true;
  code: EndpointSuccessCodeMap[E];
  data: EndpointDataMap[E];
  meta: ResponseMeta<E>;
}

export type ApiFailureForCode<E extends Endpoint, C extends EndpointErrorCodeMap[E]> = {
  ok: false;
  code: C;
  error: ApiErrorPayload<C>;
  meta: ResponseMeta<E>;
};

export type ApiFailure<E extends Endpoint> = {
  [C in EndpointErrorCodeMap[E]]: ApiFailureForCode<E, C>;
}[EndpointErrorCodeMap[E]];

export type EndpointResponse<E extends Endpoint> = ApiSuccess<E> | ApiFailure<E>;
