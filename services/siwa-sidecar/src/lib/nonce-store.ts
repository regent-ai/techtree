import { randomBytes } from "node:crypto";

import type { HexString, Result } from "../types.js";

export interface NonceRecord {
  nonce: string;
  walletAddress: HexString;
  chainId: number;
  audience?: string;
  createdAtMs: number;
  expiresAtMs: number;
  consumedAtMs?: number;
}

export interface IssueNonceInput {
  walletAddress: HexString;
  chainId: number;
  audience?: string;
  ttlSeconds: number;
}

export interface ConsumeNonceInput {
  walletAddress: HexString;
  nonce: string;
  chainId?: number;
}

export type ConsumeNonceError =
  | { kind: "not_found" }
  | { kind: "chain_mismatch"; issuedChainId: number; requestedChainId: number }
  | { kind: "expired"; expiresAtMs: number }
  | { kind: "already_used"; consumedAtMs: number };

export interface NonceStore {
  issue(input: IssueNonceInput): Promise<NonceRecord>;
  consume(input: ConsumeNonceInput): Promise<Result<NonceRecord, ConsumeNonceError>>;
}

const keyFor = (walletAddress: string, nonce: string): string =>
  `${walletAddress.toLowerCase()}:${nonce}`;

export class InMemoryNonceStore implements NonceStore {
  private readonly records = new Map<string, NonceRecord>();

  public async issue(input: IssueNonceInput): Promise<NonceRecord> {
    const now = Date.now();
    const nonce = randomBytes(16).toString("hex");
    const recordBase: NonceRecord = {
      nonce,
      walletAddress: input.walletAddress,
      chainId: input.chainId,
      createdAtMs: now,
      expiresAtMs: now + input.ttlSeconds * 1000,
    };
    const record: NonceRecord = {
      ...recordBase,
      ...(typeof input.audience === "string" ? { audience: input.audience } : {}),
    };

    this.records.set(keyFor(input.walletAddress, nonce), record);
    return record;
  }

  public async consume(input: ConsumeNonceInput): Promise<Result<NonceRecord, ConsumeNonceError>> {
    const recordKey = keyFor(input.walletAddress, input.nonce);
    const record = this.records.get(recordKey);

    if (!record) {
      return { ok: false, error: { kind: "not_found" } };
    }

    if (typeof input.chainId === "number" && record.chainId !== input.chainId) {
      return {
        ok: false,
        error: {
          kind: "chain_mismatch",
          issuedChainId: record.chainId,
          requestedChainId: input.chainId,
        },
      };
    }

    if (record.consumedAtMs !== undefined) {
      return {
        ok: false,
        error: {
          kind: "already_used",
          consumedAtMs: record.consumedAtMs,
        },
      };
    }

    if (Date.now() > record.expiresAtMs) {
      return {
        ok: false,
        error: {
          kind: "expired",
          expiresAtMs: record.expiresAtMs,
        },
      };
    }

    const consumed: NonceRecord = {
      ...record,
      consumedAtMs: Date.now(),
    };

    this.records.set(recordKey, consumed);
    return { ok: true, value: consumed };
  }
}
