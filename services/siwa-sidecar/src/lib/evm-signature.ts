import { execFile } from "node:child_process";
import { promisify } from "node:util";

import type { HexString, Result } from "../types.js";

const execFileAsync = promisify(execFile);

export type PersonalSignVerificationError = "cast_unavailable" | "verification_failed";
export type PersonalSignDeriveAddressError = "cast_unavailable" | "derive_failed";
export type PersonalSignCreateSignatureError = "cast_unavailable" | "sign_failed";

const isErrnoException = (value: unknown): value is NodeJS.ErrnoException => {
  return typeof value === "object" && value !== null && "code" in value;
};

const runCast = async (args: readonly string[]): Promise<Result<{ stdout: string }, "cast_unavailable" | "command_failed">> => {
  try {
    const output = await execFileAsync("cast", [...args], {
      timeout: 8_000,
      maxBuffer: 128 * 1024,
    });

    return {
      ok: true,
      value: {
        stdout: output.stdout.trim(),
      },
    };
  } catch (error) {
    if (isErrnoException(error) && error.code === "ENOENT") {
      return { ok: false, error: "cast_unavailable" };
    }
    return { ok: false, error: "command_failed" };
  }
};

export const verifyPersonalSignMessage = async (
  message: string,
  signature: HexString,
  expectedAddress: HexString,
): Promise<Result<true, PersonalSignVerificationError>> => {
  const result = await runCast([
    "wallet",
    "verify",
    "--address",
    expectedAddress,
    message,
    signature,
  ]);

  if (!result.ok) {
    if (result.error === "cast_unavailable") {
      return { ok: false, error: "cast_unavailable" };
    }
    return { ok: false, error: "verification_failed" };
  }

  return { ok: true, value: true };
};

export const deriveAddressFromPrivateKey = async (
  privateKey: HexString,
): Promise<Result<HexString, PersonalSignDeriveAddressError>> => {
  const result = await runCast(["wallet", "address", "--private-key", privateKey]);

  if (!result.ok) {
    if (result.error === "cast_unavailable") {
      return { ok: false, error: "cast_unavailable" };
    }
    return { ok: false, error: "derive_failed" };
  }

  const normalized = result.value.stdout;
  if (!/^0x[a-fA-F0-9]{40}$/.test(normalized)) {
    return { ok: false, error: "derive_failed" };
  }

  return { ok: true, value: normalized as HexString };
};

export const signPersonalMessageWithPrivateKey = async (
  privateKey: HexString,
  message: string,
): Promise<Result<HexString, PersonalSignCreateSignatureError>> => {
  const result = await runCast(["wallet", "sign", "--private-key", privateKey, message]);

  if (!result.ok) {
    if (result.error === "cast_unavailable") {
      return { ok: false, error: "cast_unavailable" };
    }
    return { ok: false, error: "sign_failed" };
  }

  const signature = result.value.stdout;
  if (!/^0x[a-fA-F0-9]{130}$/.test(signature)) {
    return { ok: false, error: "sign_failed" };
  }

  return { ok: true, value: signature as HexString };
};
