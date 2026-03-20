import fs from "node:fs";
import path from "node:path";

import {
  defaultConfigPath,
  loadConfig,
  ensureParentDir,
  expandHome,
  generateWallet,
  writeInitialConfigIfMissing,
} from "@regent/runtime";

import { getBooleanFlag, getFlag, type ParsedCliArgs } from "../parse.js";
import { printJson } from "../printer.js";

export async function runCreateInit(args: ParsedCliArgs): Promise<void> {
  const configPath = expandHome(getFlag(args, "config") ?? defaultConfigPath());
  const configCreated = writeInitialConfigIfMissing(configPath);
  const config = loadConfig(configPath);

  fs.mkdirSync(config.runtime.stateDir, { recursive: true });
  const socketDir = path.dirname(config.runtime.socketPath);
  const keystoreDir = path.dirname(config.wallet.keystorePath);
  const gossipsubDir = path.dirname(config.gossipsub.peerIdPath);
  const xmtpDir = path.dirname(config.xmtp.dbPath);
  const xmtpPolicyDir = path.dirname(config.xmtp.publicPolicyPath);

  fs.mkdirSync(socketDir, { recursive: true });
  fs.mkdirSync(keystoreDir, { recursive: true });
  fs.mkdirSync(gossipsubDir, { recursive: true });
  fs.mkdirSync(xmtpDir, { recursive: true });
  fs.mkdirSync(xmtpPolicyDir, { recursive: true });

  printJson({
    ok: true,
    configPath,
    configCreated,
    stateDir: config.runtime.stateDir,
    socketDir,
    keystoreDir,
    gossipsubDir,
    xmtpDir,
    xmtpPolicyDir,
  });
}

export async function runCreateWallet(args: ParsedCliArgs): Promise<void> {
  const wallet = await generateWallet();
  const writeEnv = getBooleanFlag(args, "write-env");
  const devFile = getFlag(args, "dev-file");

  if (devFile) {
    const resolvedPath = path.resolve(expandHome(devFile));
    ensureParentDir(resolvedPath);
    fs.writeFileSync(resolvedPath, `${JSON.stringify({ privateKey: wallet.privateKey }, null, 2)}\n`, "utf8");
  }

  printJson({
    address: wallet.address,
    ...(writeEnv
      ? {
          export: `export REGENT_WALLET_PRIVATE_KEY=${wallet.privateKey}`,
        }
      : {}),
    ...(devFile ? { devFile: path.resolve(expandHome(devFile)) } : {}),
  });
}
