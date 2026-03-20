import { execFile as execFileCallback, spawnSync } from "node:child_process";
import { promisify } from "node:util";
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";

import type { RegentConfig, RegentXmtpEnv, XmtpClientInfo, XmtpInitResult, XmtpStatus } from "@regent/types";

import { generateWallet } from "../agent/wallet.js";
import { RegentError, errorMessage } from "../errors.js";
import { ensureParentDir } from "../paths.js";

const execFile = promisify(execFileCallback);
const require = createRequire(import.meta.url);
const SECRET_FILE_MODE = 0o600;

const DEFAULT_PUBLIC_POLICY = `You are representing your owner to a third party.
Be helpful and conversational, but keep responses limited to general conversation.
Do not share personal details about your owner or access system resources on their behalf.
If unsure whether something is appropriate, err on the side of caution.
`;

interface XmtpCliInfoPayload {
  properties?: {
    address?: string;
    inboxId?: string;
    installationId?: string;
    isRegistered?: boolean;
    appVersion?: string;
    libxmtpVersion?: string;
  };
}

interface XmtpCliInboxIdPayload {
  inboxId?: string | null;
  found?: boolean;
}

const resolveXmtpCliBinPath = (): string => {
  let packageJsonPath: string;
  try {
    packageJsonPath = require.resolve("@xmtp/cli/package.json");
  } catch (error) {
    throw new RegentError("xmtp_cli_missing", "missing @xmtp/cli dependency in runtime workspace", error);
  }

  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8")) as { bin?: { xmtp?: string } };
  const relativeBin = packageJson.bin?.xmtp;
  if (!relativeBin) {
    throw new RegentError("xmtp_cli_missing", "unable to resolve the xmtp CLI binary from @xmtp/cli");
  }

  return path.resolve(path.dirname(packageJsonPath), relativeBin);
};

const runXmtpCli = async (args: string[]): Promise<string> => {
  const binPath = resolveXmtpCliBinPath();
  try {
    const { stdout } = await execFile(process.execPath, [binPath, ...args], {
      encoding: "utf8",
      env: {
        ...process.env,
        NO_COLOR: "1",
      },
      maxBuffer: 1024 * 1024,
    });
    return stdout.trim();
  } catch (error) {
    const failure = error as {
      stdout?: string;
      stderr?: string;
      message?: string;
    };
    throw new RegentError(
      "xmtp_cli_error",
      failure.stderr?.trim() || failure.stdout?.trim() || failure.message || "xmtp CLI command failed",
      error,
    );
  }
};

const writeFileWithMode = (filePath: string, value: string, mode = SECRET_FILE_MODE): void => {
  ensureParentDir(filePath);
  fs.writeFileSync(filePath, `${value.trim()}\n`, "utf8");
  fs.chmodSync(filePath, mode);
};

const readRequiredFile = (filePath: string, kind: string): string => {
  if (!fs.existsSync(filePath)) {
    throw new RegentError("xmtp_not_initialized", `missing XMTP ${kind} at ${filePath}; run \`regent xmtp init\``);
  }

  return fs.readFileSync(filePath, "utf8").trim();
};

const readOptionalFile = (filePath: string): string | null => {
  if (!fs.existsSync(filePath)) {
    return null;
  }

  return fs.readFileSync(filePath, "utf8").trim() || null;
};

const cliConnectionArgs = (config: RegentConfig["xmtp"]): string[] => {
  const walletKey = readRequiredFile(config.walletKeyPath, "wallet key");
  const dbEncryptionKey = readRequiredFile(config.dbEncryptionKeyPath, "database encryption key");

  return [
    "--env",
    config.env,
    "--wallet-key",
    walletKey,
    "--db-encryption-key",
    dbEncryptionKey,
    "--db-path",
    config.dbPath,
    "--log-level",
    "off",
  ];
};

const parseInitOutput = (stdout: string, env: RegentXmtpEnv): { walletKey: string; dbEncryptionKey: string } => {
  const entries = Object.fromEntries(
    stdout
      .trim()
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line) => {
        const [key, ...rest] = line.split("=");
        return [key, rest.join("=")];
      }),
  ) as Record<string, string>;

  const walletKey = entries.XMTP_WALLET_KEY;
  const dbEncryptionKey = entries.XMTP_DB_ENCRYPTION_KEY;
  const resolvedEnv = entries.XMTP_ENV;

  if (!walletKey || !dbEncryptionKey || resolvedEnv !== env) {
    throw new RegentError("xmtp_cli_error", "xmtp init did not return the expected key material");
  }

  return {
    walletKey,
    dbEncryptionKey,
  };
};

const normalizeClientInfo = (payload: XmtpCliInfoPayload): XmtpClientInfo => {
  const address = payload.properties?.address;
  const inboxId = payload.properties?.inboxId;
  const installationId = payload.properties?.installationId;

  if (!address || !inboxId || !installationId) {
    throw new RegentError("xmtp_cli_error", "xmtp client info returned an incomplete payload");
  }

  return {
    address: address as `0x${string}`,
    inboxId,
    installationId,
    isRegistered: payload.properties?.isRegistered === true,
    appVersion: payload.properties?.appVersion,
    libxmtpVersion: payload.properties?.libxmtpVersion,
  };
};

export const ensureXmtpPolicyFile = (config: RegentConfig["xmtp"]): { created: boolean; path: string } => {
  if (fs.existsSync(config.publicPolicyPath)) {
    return { created: false, path: config.publicPolicyPath };
  }

  ensureParentDir(config.publicPolicyPath);
  fs.writeFileSync(config.publicPolicyPath, DEFAULT_PUBLIC_POLICY, "utf8");
  return { created: true, path: config.publicPolicyPath };
};

export const xmtpMaterialExists = (config: RegentConfig["xmtp"]): boolean => {
  return fs.existsSync(config.walletKeyPath) && fs.existsSync(config.dbEncryptionKeyPath);
};

export const loadXmtpClientInfo = async (config: RegentConfig["xmtp"]): Promise<XmtpClientInfo> => {
  const stdout = await runXmtpCli(["client", "info", "--json", ...cliConnectionArgs(config)]);
  return normalizeClientInfo(JSON.parse(stdout) as XmtpCliInfoPayload);
};

export const resolveXmtpInboxId = async (
  config: RegentConfig["xmtp"],
  identifier: `0x${string}`,
): Promise<string | null> => {
  const stdout = await runXmtpCli(["client", "inbox-id", "--json", "-i", identifier, ...cliConnectionArgs(config)]);
  const payload = JSON.parse(stdout) as XmtpCliInboxIdPayload;
  return payload.found === false ? null : (payload.inboxId ?? null);
};

export const ensureXmtpMaterial = async (
  config: RegentConfig["xmtp"],
): Promise<{ createdWalletKey: boolean; createdDbEncryptionKey: boolean }> => {
  const walletExists = fs.existsSync(config.walletKeyPath);
  const dbKeyExists = fs.existsSync(config.dbEncryptionKeyPath);

  if (walletExists && dbKeyExists) {
    return {
      createdWalletKey: false,
      createdDbEncryptionKey: false,
    };
  }

  const stdout = await runXmtpCli(["init", "--stdout", "--env", config.env]);
  const initResult = parseInitOutput(stdout, config.env);

  if (!walletExists) {
    writeFileWithMode(config.walletKeyPath, initResult.walletKey);
  }

  if (!dbKeyExists) {
    writeFileWithMode(config.dbEncryptionKeyPath, initResult.dbEncryptionKey);
  }

  return {
    createdWalletKey: !walletExists,
    createdDbEncryptionKey: !dbKeyExists,
  };
};

export const initializeXmtp = async (
  config: RegentConfig["xmtp"],
  configPath: string,
): Promise<XmtpInitResult> => {
  const { createdWalletKey, createdDbEncryptionKey } = await ensureXmtpMaterial(config);
  const { created: createdPolicyFile } = ensureXmtpPolicyFile(config);
  const client = await loadXmtpClientInfo(config);

  return {
    configPath,
    enabled: config.enabled,
    env: config.env,
    dbPath: config.dbPath,
    dbEncryptionKeyPath: config.dbEncryptionKeyPath,
    walletKeyPath: config.walletKeyPath,
    publicPolicyPath: config.publicPolicyPath,
    ownerInboxIds: [...config.ownerInboxIds],
    trustedInboxIds: [...config.trustedInboxIds],
    profiles: { ...config.profiles },
    createdWalletKey,
    createdDbEncryptionKey,
    createdPolicyFile,
    client,
  };
};

export const generateStandaloneXmtpWallet = async (): Promise<`0x${string}`> => {
  const wallet = await generateWallet();
  return wallet.privateKey;
};

export const getXmtpStatus = async (
  config: RegentConfig["xmtp"],
  options?: { started?: boolean; lastError?: string | null },
): Promise<XmtpStatus> => {
  const configured = xmtpMaterialExists(config) && fs.existsSync(config.publicPolicyPath);
  const started = options?.started ?? false;

  if (!config.enabled) {
    return {
      enabled: false,
      status: "disabled",
      configured,
      started,
      env: config.env,
      dbPath: config.dbPath,
      walletKeyPath: config.walletKeyPath,
      dbEncryptionKeyPath: config.dbEncryptionKeyPath,
      publicPolicyPath: config.publicPolicyPath,
      ownerInboxIds: [...config.ownerInboxIds],
      trustedInboxIds: [...config.trustedInboxIds],
      profiles: { ...config.profiles },
      note: "XMTP is disabled in config",
      lastError: options?.lastError ?? null,
      client: null,
    };
  }

  if (!configured) {
    return {
      enabled: true,
      status: "degraded",
      configured: false,
      started,
      env: config.env,
      dbPath: config.dbPath,
      walletKeyPath: config.walletKeyPath,
      dbEncryptionKeyPath: config.dbEncryptionKeyPath,
      publicPolicyPath: config.publicPolicyPath,
      ownerInboxIds: [...config.ownerInboxIds],
      trustedInboxIds: [...config.trustedInboxIds],
      profiles: { ...config.profiles },
      note: "XMTP material is incomplete; run `regent xmtp init`",
      lastError: options?.lastError ?? null,
      client: null,
    };
  }

  try {
    const client = await loadXmtpClientInfo(config);
    return {
      enabled: true,
      status: started ? "stub" : "stopped",
      configured: true,
      started,
      env: config.env,
      dbPath: config.dbPath,
      walletKeyPath: config.walletKeyPath,
      dbEncryptionKeyPath: config.dbEncryptionKeyPath,
      publicPolicyPath: config.publicPolicyPath,
      ownerInboxIds: [...config.ownerInboxIds],
      trustedInboxIds: [...config.trustedInboxIds],
      profiles: { ...config.profiles },
      note: started
        ? "XMTP identity is online, but Regent does not yet route inbound conversations into a managed agent session"
        : "XMTP identity is initialized and ready",
      lastError: options?.lastError ?? null,
      client,
    };
  } catch (error) {
    return {
      enabled: true,
      status: started ? "error" : "degraded",
      configured: true,
      started,
      env: config.env,
      dbPath: config.dbPath,
      walletKeyPath: config.walletKeyPath,
      dbEncryptionKeyPath: config.dbEncryptionKeyPath,
      publicPolicyPath: config.publicPolicyPath,
      ownerInboxIds: [...config.ownerInboxIds],
      trustedInboxIds: [...config.trustedInboxIds],
      profiles: { ...config.profiles },
      note: "XMTP CLI probe failed",
      lastError: errorMessage(error),
      client: null,
    };
  }
};

export const openXmtpPolicyInEditor = (config: RegentConfig["xmtp"]): { opened: boolean; editor: string | null } => {
  const editor = process.env.EDITOR?.trim() || null;
  if (!editor || !process.stdin.isTTY) {
    return {
      opened: false,
      editor,
    };
  }

  const result = spawnSync(editor, [config.publicPolicyPath], {
    stdio: "inherit",
    shell: true,
  });

  if (result.status !== 0) {
    throw new RegentError(
      "xmtp_editor_failed",
      `editor command failed for ${config.publicPolicyPath}`,
      result.error,
    );
  }

  return {
    opened: true,
    editor,
  };
};

export const readXmtpWalletKey = (config: RegentConfig["xmtp"]): string | null => readOptionalFile(config.walletKeyPath);
