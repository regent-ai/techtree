import {
  addXmtpGroupMembers,
  createXmtpGroup,
  defaultConfigPath,
  ensureXmtpPolicyFile,
  getXmtpStatus,
  initializeXmtp,
  listXmtpAllowlist,
  listXmtpGroups,
  loadConfig,
  openXmtpPolicyInEditor,
  resolveXmtpIdentifier,
  resolveXmtpInboxId,
  revokeAllOtherXmtpInstallations,
  rotateXmtpDbKey,
  rotateXmtpWallet,
  showXmtpPolicy,
  testXmtpDm,
  updateXmtpAllowlist,
  validateXmtpPolicy,
  writeConfigReplacement,
} from "@regent/runtime";

import { daemonCall } from "../daemon-client.js";
import { getBooleanFlag, getFlag, type ParsedCliArgs } from "../parse.js";
import { printJson } from "../printer.js";
import { runDoctorCommand } from "./doctor.js";

const resolveConfigPath = (configPath?: string): string => configPath ?? defaultConfigPath();

const requirePositional = (args: ParsedCliArgs, index: number, name: string): string => {
  const value = args.positionals[index];
  if (!value) {
    throw new Error(`missing required argument: ${name}`);
  }

  return value;
};

const requireAddress = (args: ParsedCliArgs, flag = "address"): `0x${string}` => {
  const address = getFlag(args, flag) ?? getFlag(args, "wallet-address");
  if (!address) {
    throw new Error(`missing required argument: --${flag}`);
  }

  return address as `0x${string}`;
};

const requireInboxOrAddress = (args: ParsedCliArgs): string => {
  return getFlag(args, "inbox-id") ?? getFlag(args, "address") ?? getFlag(args, "wallet-address") ?? "";
};

const resolveStatus = async (configPath?: string) => {
  const resolvedConfigPath = resolveConfigPath(configPath);

  try {
    return await daemonCall("xmtp.status", undefined, resolvedConfigPath);
  } catch {
    const config = loadConfig(resolvedConfigPath);
    return getXmtpStatus(config.xmtp);
  }
};

const updateAllowlistConfig = async (
  args: ParsedCliArgs,
  configPath: string,
  list: "owner" | "trusted",
  action: "add" | "remove",
): Promise<void> => {
  const resolvedConfigPath = resolveConfigPath(configPath);
  const config = loadConfig(resolvedConfigPath);
  const identifier = requireInboxOrAddress(args);

  if (!identifier) {
    throw new Error("missing required argument: --address or --inbox-id");
  }

  const inboxId = await resolveXmtpIdentifier(config.xmtp, identifier);
  const current = list === "owner" ? config.xmtp.ownerInboxIds : config.xmtp.trustedInboxIds;
  const next = updateXmtpAllowlist(current, action, inboxId).updated;

  writeConfigReplacement(resolvedConfigPath, {
    ...config,
    xmtp: {
      ...config.xmtp,
      [list === "owner" ? "ownerInboxIds" : "trustedInboxIds"]: next,
    },
  });

  printJson({
    ok: true,
    updated: next,
    changedInboxId: inboxId,
  });
};

export async function runXmtpInit(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const resolvedConfigPath = resolveConfigPath(configPath);
  let config = loadConfig(resolvedConfigPath);

  config = writeConfigReplacement(resolvedConfigPath, {
    ...config,
    xmtp: {
      ...config.xmtp,
      enabled: true,
    },
  });

  let result = await initializeXmtp(config.xmtp, resolvedConfigPath);
  const owner = getFlag(args, "owner");
  if (owner) {
    const inboxId = await resolveXmtpIdentifier(config.xmtp, owner);
    config = writeConfigReplacement(resolvedConfigPath, {
      ...config,
      xmtp: {
        ...config.xmtp,
        ownerInboxIds: Array.from(new Set([...config.xmtp.ownerInboxIds, inboxId])),
      },
    });
    result = {
      ...result,
      enabled: true,
      ownerInboxIds: [...config.xmtp.ownerInboxIds],
    };
  }

  printJson({
    ok: true,
    ...result,
  });

  return 0;
}

export async function runXmtpInfo(configPath?: string): Promise<void> {
  const resolvedConfigPath = resolveConfigPath(configPath);
  const config = loadConfig(resolvedConfigPath);

  printJson({
    config: config.xmtp,
    status: await resolveStatus(resolvedConfigPath),
  });
}

export async function runXmtpStatus(configPath?: string): Promise<void> {
  printJson(await resolveStatus(configPath));
}

export async function runXmtpResolve(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const config = loadConfig(resolveConfigPath(configPath));
  const address = requireAddress(args);
  const inboxId = await resolveXmtpInboxId(config.xmtp, address);

  printJson({
    address,
    inboxId,
  });
}

export async function runXmtpOwnerAdd(args: ParsedCliArgs, configPath?: string): Promise<void> {
  await updateAllowlistConfig(args, resolveConfigPath(configPath), "owner", "add");
}

export async function runXmtpOwnerList(configPath?: string): Promise<void> {
  const config = loadConfig(resolveConfigPath(configPath));
  printJson(listXmtpAllowlist(config.xmtp, "owner"));
}

export async function runXmtpOwnerRemove(args: ParsedCliArgs, configPath?: string): Promise<void> {
  await updateAllowlistConfig(args, resolveConfigPath(configPath), "owner", "remove");
}

export async function runXmtpTrustedAdd(args: ParsedCliArgs, configPath?: string): Promise<void> {
  await updateAllowlistConfig(args, resolveConfigPath(configPath), "trusted", "add");
}

export async function runXmtpTrustedList(configPath?: string): Promise<void> {
  const config = loadConfig(resolveConfigPath(configPath));
  printJson(listXmtpAllowlist(config.xmtp, "trusted"));
}

export async function runXmtpTrustedRemove(args: ParsedCliArgs, configPath?: string): Promise<void> {
  await updateAllowlistConfig(args, resolveConfigPath(configPath), "trusted", "remove");
}

export async function runXmtpPolicyInit(configPath?: string): Promise<void> {
  const config = loadConfig(resolveConfigPath(configPath));
  printJson({
    ok: true,
    ...ensureXmtpPolicyFile(config.xmtp),
  });
}

export async function runXmtpPolicyEdit(configPath?: string): Promise<void> {
  const config = loadConfig(resolveConfigPath(configPath));
  printJson(openXmtpPolicyInEditor(config.xmtp));
}

export async function runXmtpPolicyShow(configPath?: string): Promise<void> {
  const config = loadConfig(resolveConfigPath(configPath));
  printJson(showXmtpPolicy(config.xmtp));
}

export async function runXmtpPolicyValidate(configPath?: string): Promise<number> {
  const config = loadConfig(resolveConfigPath(configPath));
  const result = validateXmtpPolicy(config.xmtp);
  printJson(result);
  return result.ok ? 0 : 1;
}

export async function runXmtpDoctor(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const normalizedArgs: ParsedCliArgs = {
    ...args,
    positionals: ["doctor", "xmtp", ...args.positionals.slice(2)],
  };

  return runDoctorCommand(normalizedArgs, resolveConfigPath(configPath));
}

export async function runXmtpTestDm(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const config = loadConfig(resolveConfigPath(configPath));
  const to = requireAddress(args, "to");
  const message = getFlag(args, "message");

  if (!message) {
    throw new Error("missing required argument: --message");
  }

  printJson(await testXmtpDm(config.xmtp, to, message));
}

export async function runXmtpGroupCreate(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const config = loadConfig(resolveConfigPath(configPath));
  const members = args.positionals.slice(3);

  printJson(
    await createXmtpGroup(config.xmtp, members, {
      name: getFlag(args, "name"),
      description: getFlag(args, "description"),
      imageUrl: getFlag(args, "image-url"),
      permissions: (getFlag(args, "permissions") as "all-members" | "admin-only" | undefined) ?? undefined,
    }),
  );
}

export async function runXmtpGroupAddMember(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const config = loadConfig(resolveConfigPath(configPath));
  const conversationId = requirePositional(args, 3, "conversation-id");
  const members = args.positionals.slice(4);

  printJson(await addXmtpGroupMembers(config.xmtp, conversationId, members));
}

export async function runXmtpGroupList(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const config = loadConfig(resolveConfigPath(configPath));
  printJson(await listXmtpGroups(config.xmtp, { sync: getBooleanFlag(args, "sync") }));
}

export async function runXmtpRevokeOtherInstallations(configPath?: string): Promise<void> {
  const config = loadConfig(resolveConfigPath(configPath));
  printJson(await revokeAllOtherXmtpInstallations(config.xmtp));
}

export async function runXmtpRotateDbKey(configPath?: string): Promise<void> {
  const config = loadConfig(resolveConfigPath(configPath));
  printJson(await rotateXmtpDbKey(config.xmtp));
}

export async function runXmtpRotateWallet(configPath?: string): Promise<void> {
  const config = loadConfig(resolveConfigPath(configPath));
  printJson(await rotateXmtpWallet(config.xmtp));
}
