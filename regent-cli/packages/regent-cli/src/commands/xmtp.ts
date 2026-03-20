import path from "node:path";

import {
  defaultConfigPath,
  ensureXmtpPolicyFile,
  expandHome,
  getXmtpStatus,
  initializeXmtp,
  loadConfig,
  openXmtpPolicyInEditor,
  resolveXmtpInboxId,
  runScopedDoctor,
  writeConfigReplacement,
  writeInitialConfigIfMissing,
  xmtpDefaultsForRoot,
} from "@regent/runtime";
import type { DoctorReport, RegentConfig, RegentXmtpEnv } from "@regent/types";

import { getBooleanFlag, getFlag, type ParsedCliArgs } from "../parse.js";
import { printJson, printText } from "../printer.js";
import { renderDoctorReport } from "../printers/doctorPrinter.js";
import { CliUsageError } from "./doctor.js";

const ensureConfigPath = (configPath?: string): string => {
  const resolved = expandHome(configPath ?? defaultConfigPath());
  writeInitialConfigIfMissing(resolved);
  return resolved;
};

const loadConfigForEdit = (configPath?: string): { configPath: string; config: RegentConfig } => {
  const resolvedConfigPath = ensureConfigPath(configPath);
  return {
    configPath: resolvedConfigPath,
    config: loadConfig(resolvedConfigPath),
  };
};

const uniqueStrings = (values: readonly string[]): string[] => {
  return [...new Set(values)];
};

const parseAddressFlag = (args: ParsedCliArgs): `0x${string}` => {
  const value = getFlag(args, "address");
  if (!value || !/^0x[0-9a-fA-F]{40}$/.test(value)) {
    throw new CliUsageError("missing or invalid --address");
  }

  return value as `0x${string}`;
};

const nextXmtpConfig = (
  configPath: string,
  config: RegentConfig,
  envOverride?: RegentXmtpEnv,
): RegentConfig["xmtp"] => {
  if (!envOverride) {
    return {
      ...config.xmtp,
      enabled: true,
    };
  }

  const defaults = xmtpDefaultsForRoot(path.dirname(configPath), envOverride);
  return {
    ...defaults,
    enabled: true,
    ownerInboxIds: [...config.xmtp.ownerInboxIds],
    trustedInboxIds: [...config.xmtp.trustedInboxIds],
    publicPolicyPath: config.xmtp.publicPolicyPath,
    profiles: { ...config.xmtp.profiles },
  };
};

const renderScopedDoctor = (report: DoctorReport, args: ParsedCliArgs): number => {
  const json = getBooleanFlag(args, "json");
  const verbose = getBooleanFlag(args, "verbose");
  const quiet = getBooleanFlag(args, "quiet");
  const onlyFailures = getBooleanFlag(args, "only-failures");
  const ci = getBooleanFlag(args, "ci");

  if (json) {
    printJson(report);
  } else {
    printText(renderDoctorReport(report, { verbose, quiet, onlyFailures, ci }));
  }

  return report.checks.some((check) => check.details?.internal === true)
    ? 3
    : report.summary.fail > 0 ? 1 : 0;
};

export async function runXmtpInit(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const { configPath: resolvedConfigPath, config } = loadConfigForEdit(configPath);
  const envFlag = getFlag(args, "env");
  const env = envFlag as RegentXmtpEnv | undefined;
  if (envFlag && envFlag !== "local" && envFlag !== "dev" && envFlag !== "production") {
    throw new CliUsageError("invalid --env; expected local, dev, or production");
  }

  const nextConfig: RegentConfig = {
    ...config,
    xmtp: nextXmtpConfig(resolvedConfigPath, config, env),
  };

  const written = writeConfigReplacement(resolvedConfigPath, nextConfig);
  const result = await initializeXmtp(written.xmtp, resolvedConfigPath);
  printJson({
    ok: true,
    ...result,
  });
  return 0;
}

export async function runXmtpInfo(configPath?: string): Promise<void> {
  const { config } = loadConfigForEdit(configPath);
  printJson(await getXmtpStatus(config.xmtp));
}

export async function runXmtpStatus(configPath?: string): Promise<void> {
  return runXmtpInfo(configPath);
}

export async function runXmtpResolve(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const { config } = loadConfigForEdit(configPath);
  const address = parseAddressFlag(args);
  const inboxId = await resolveXmtpInboxId(config.xmtp, address);
  printJson({
    ok: inboxId !== null,
    address,
    inboxId,
  });
}

export async function runXmtpOwnerAdd(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const { configPath: resolvedConfigPath, config } = loadConfigForEdit(configPath);
  const inboxIdFlag = getFlag(args, "inbox-id");
  const addressFlag = getFlag(args, "address");

  if ((inboxIdFlag ? 1 : 0) + (addressFlag ? 1 : 0) !== 1) {
    throw new CliUsageError("provide exactly one of --address or --inbox-id");
  }

  const inboxId = inboxIdFlag
    ? inboxIdFlag
    : await resolveXmtpInboxId(config.xmtp, parseAddressFlag(args));

  if (!inboxId) {
    throw new CliUsageError("unable to resolve an XMTP inbox ID for the given address");
  }

  const nextConfig: RegentConfig = {
    ...config,
    xmtp: {
      ...config.xmtp,
      ownerInboxIds: uniqueStrings([...config.xmtp.ownerInboxIds, inboxId]),
    },
  };

  const written = writeConfigReplacement(resolvedConfigPath, nextConfig);
  printJson({
    ok: true,
    ownerInboxIds: written.xmtp.ownerInboxIds,
    addedInboxId: inboxId,
  });
}

export async function runXmtpPolicyInit(configPath?: string): Promise<void> {
  const { config } = loadConfigForEdit(configPath);
  const result = ensureXmtpPolicyFile(config.xmtp);
  printJson({
    ok: true,
    path: result.path,
    created: result.created,
  });
}

export async function runXmtpPolicyEdit(configPath?: string): Promise<void> {
  const { config } = loadConfigForEdit(configPath);
  const result = ensureXmtpPolicyFile(config.xmtp);
  const editorResult = openXmtpPolicyInEditor(config.xmtp);
  printJson({
    ok: true,
    path: result.path,
    created: result.created,
    opened: editorResult.opened,
    editor: editorResult.editor,
  });
}

export async function runXmtpDoctor(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const report = await runScopedDoctor(
    {
      scope: "transports",
      json: getBooleanFlag(args, "json"),
      verbose: getBooleanFlag(args, "verbose"),
      fix: getBooleanFlag(args, "fix"),
    },
    { configPath },
  );

  return renderScopedDoctor(report, args);
}
