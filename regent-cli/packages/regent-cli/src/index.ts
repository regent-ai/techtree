#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { defaultConfigPath, expandHome, RegentError } from "@regent/runtime";

import {
  runAgentbookLookup,
  runAgentbookRegister,
  runAgentbookSessionsWatch,
  runAgentbookVerifyHeader,
} from "./commands/agentbook.js";
import {
  runAutolaunchAgentReadiness,
  runAutolaunchAgentsList,
  runAutolaunchEnsPlan,
  runAutolaunchEnsPrepareBidirectional,
  runAutolaunchEnsPrepareErc8004,
  runAutolaunchEnsPrepareEnsip25,
  runAutolaunchAgentShow,
  runAutolaunchAuctionShow,
  runAutolaunchAuctionsList,
  runAutolaunchBidsClaim,
  runAutolaunchBidsExit,
  runAutolaunchBidsMine,
  runAutolaunchBidsPlace,
  runAutolaunchBidsQuote,
  runAutolaunchIdentitiesList,
  runAutolaunchIdentitiesMint,
  runAutolaunchJobsWatch,
  runAutolaunchLaunchCreate,
  runAutolaunchLaunchPreview,
} from "./commands/autolaunch.js";
import { runAuthSiwaLogin, runAuthSiwaLogout, runAuthSiwaStatus } from "./commands/auth.js";
import { runConfigRead, runConfigWrite } from "./commands/config.js";
import { runCreateInit, runCreateWallet } from "./commands/create.js";
import { CliUsageError, runDoctorCommand } from "./commands/doctor.js";
import { runGossipsubStatus } from "./commands/gossipsub.js";
import { runRuntime } from "./commands/run.js";
import {
  runXmtpDoctor,
  runXmtpInfo,
  runXmtpInit,
  runXmtpOwnerAdd,
  runXmtpPolicyEdit,
  runXmtpPolicyInit,
  runXmtpResolve,
  runXmtpStatus,
} from "./commands/xmtp.js";
import {
  runTechtreeCommentAdd,
  runTechtreeActivity,
  runTechtreeInbox,
  runTechtreeNodeChildren,
  runTechtreeNodeComments,
  runTechtreeNodeCreate,
  runTechtreeNodeGet,
  runTechtreeNodeWorkPacket,
  runTechtreeNodesList,
  runTechtreeOpportunities,
  runTechtreeSearch,
  runTechtreeStar,
  runTechtreeStatus,
  runTechtreeUnwatch,
  runTechtreeUnstar,
  runTechtreeWatch,
  runTechtreeWatchList,
  runTechtreeWatchTail,
} from "./commands/techtree.js";
import { runTrollboxHistory, runTrollboxPost, runTrollboxTail } from "./commands/trollbox.js";
import { getFlag, parseCliArgs, requireArg, type ParsedCliArgs } from "./parse.js";
import { printError, printJson } from "./printer.js";

interface CliCommand {
  match: (args: ParsedCliArgs) => boolean;
  usage: string;
  run: (args: ParsedCliArgs, configPath?: string) => Promise<number | void>;
}

const requireNodeId = (value: string | undefined): number => {
  if (!value) {
    throw new Error("missing required node id");
  }

  const parsed = Number.parseInt(value, 10);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw new Error("invalid node id");
  }

  return parsed;
};

export const parseConfigPath = (args: string[]): string | undefined => {
  return parseConfigPathInternal(parseCliArgs(args));
};

export const positionalCliArgs = (args: string[]): string[] => {
  return [...parseCliArgs(args).positionals];
};

export async function runCli(rawArgs = process.argv.slice(2)): Promise<number | void> {
  const args = parseCliArgs(rawArgs);
  const configPath = parseConfigPathInternal(args);
  for (const command of CLI_COMMANDS) {
    if (command.match(args)) {
      return command.run(args, configPath);
    }
  }

  printJson({
    usage: [
      ...CLI_COMMANDS.map((command) => command.usage),
      `default config: ${configPath ?? defaultConfigPath()}`,
    ],
  });
}

export async function runCliEntrypoint(rawArgs = process.argv.slice(2)): Promise<number> {
  try {
    const exitCode = await runCli(rawArgs);
    return typeof exitCode === "number" ? exitCode : 0;
  } catch (error) {
    printError(error);
    if (error instanceof CliUsageError) {
      return 2;
    }

    if (error instanceof RegentError && error.code === "doctor_internal_error") {
      return 3;
    }

    return 1;
  }
}

const parseConfigPathInternal = (args: ParsedCliArgs): string | undefined => {
  const configFlag = getFlag(args, "config");
  return configFlag ? expandHome(configFlag) : undefined;
};

const hasCommandPath = (args: ParsedCliArgs, expected: readonly string[]): boolean =>
  expected.every((value, index) => args.positionals[index] === value) && args.positionals.length >= expected.length;

const CLI_COMMANDS: readonly CliCommand[] = [
  {
    match: (args) => hasCommandPath(args, ["agentbook", "register"]),
    usage: "regent agentbook register <agent-address> [--network <world|base|base-sepolia>] [--auto] [--manual] [--relay-url <url>] [--watch]",
    run: (args) => runAgentbookRegister(args),
  },
  {
    match: (args) => hasCommandPath(args, ["agentbook", "sessions", "watch"]),
    usage: "regent agentbook sessions watch <session-id> [--interval <seconds>]",
    run: (args) => runAgentbookSessionsWatch(args),
  },
  {
    match: (args) => hasCommandPath(args, ["agentbook", "lookup"]),
    usage: "regent agentbook lookup --address <address> [--network <world|base|base-sepolia>]",
    run: (args) => runAgentbookLookup(args),
  },
  {
    match: (args) => hasCommandPath(args, ["agentbook", "verify-header"]),
    usage: "regent agentbook verify-header --header <agentkit-header> --resource-uri <url>",
    run: (args) => runAgentbookVerifyHeader(args),
  },
  {
    match: (args) => hasCommandPath(args, ["doctor"]),
    usage: "regent doctor [runtime|auth|techtree|transports] [--json] [--verbose] [--fix] [--full] [--quiet] [--only-failures] [--ci]",
    run: (args, configPath) => runDoctorCommand(args, configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["run"]),
    usage: "regent run",
    run: (_args, configPath) => runRuntime(configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["create", "init"]),
    usage: "regent create init",
    run: (args) => runCreateInit(args),
  },
  {
    match: (args) => hasCommandPath(args, ["create", "wallet"]),
    usage: "regent create wallet",
    run: (args) => runCreateWallet(args),
  },
  {
    match: (args) => hasCommandPath(args, ["config", "read"]),
    usage: "regent config read [--config <path>]",
    run: (args) => runConfigRead(args),
  },
  {
    match: (args) => hasCommandPath(args, ["config", "write"]),
    usage: "regent config write --input @file.json [--config <path>]",
    run: (args) => runConfigWrite(args),
  },
  {
    match: (args) => hasCommandPath(args, ["auth", "siwa", "login"]),
    usage: "regent auth siwa login",
    run: (args, configPath) => runAuthSiwaLogin(args, configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["auth", "siwa", "status"]),
    usage: "regent auth siwa status",
    run: (_args, configPath) => runAuthSiwaStatus(configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["auth", "siwa", "logout"]),
    usage: "regent auth siwa logout",
    run: (_args, configPath) => runAuthSiwaLogout(configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["techtree", "status"]),
    usage: "regent techtree status",
    run: (_args, configPath) => runTechtreeStatus(configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["techtree", "nodes", "list"]),
    usage: "regent techtree nodes list",
    run: (args, configPath) => runTechtreeNodesList(args, configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["techtree", "node", "get"]),
    usage: "regent techtree node get <id>",
    run: (args, configPath) => runTechtreeNodeGet(requireNodeId(args.positionals[3]), configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["techtree", "node", "children"]),
    usage: "regent techtree node children <id>",
    run: (args, configPath) => runTechtreeNodeChildren(args, requireNodeId(args.positionals[3]), configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["techtree", "node", "comments"]),
    usage: "regent techtree node comments <id>",
    run: (args, configPath) => runTechtreeNodeComments(args, requireNodeId(args.positionals[3]), configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["techtree", "activity"]),
    usage: "regent techtree activity [--limit <n>]",
    run: (args, configPath) => runTechtreeActivity(args, configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["techtree", "search"]),
    usage: "regent techtree search --query <q> [--limit <n>]",
    run: (args, configPath) => runTechtreeSearch(args, configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["techtree", "node", "work-packet"]),
    usage: "regent techtree node work-packet <id>",
    run: (args, configPath) => runTechtreeNodeWorkPacket(requireNodeId(args.positionals[3]), configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["techtree", "node", "create"]),
    usage: "regent techtree node create ...",
    run: (args, configPath) => runTechtreeNodeCreate(args, configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["techtree", "comment", "add"]),
    usage: "regent techtree comment add ...",
    run: (args, configPath) => runTechtreeCommentAdd(args, configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["techtree", "watch", "list"]),
    usage: "regent techtree watch list",
    run: (_args, configPath) => runTechtreeWatchList(configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["techtree", "watch", "tail"]),
    usage: "regent techtree watch tail",
    run: (_args, configPath) => runTechtreeWatchTail(configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["techtree", "watch"]),
    usage: "regent techtree watch <id>",
    run: (args, configPath) => runTechtreeWatch(requireNodeId(args.positionals[2]), configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["techtree", "unwatch"]),
    usage: "regent techtree unwatch <id>",
    run: (args, configPath) => runTechtreeUnwatch(requireNodeId(args.positionals[2]), configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["techtree", "inbox"]),
    usage: "regent techtree inbox",
    run: (args, configPath) => runTechtreeInbox(args, configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["techtree", "opportunities"]),
    usage: "regent techtree opportunities",
    run: (args, configPath) => runTechtreeOpportunities(args, configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["techtree", "star"]),
    usage: "regent techtree star <id>",
    run: (args, configPath) => runTechtreeStar(requireNodeId(args.positionals[2]), configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["techtree", "unstar"]),
    usage: "regent techtree unstar <id>",
    run: (args, configPath) => runTechtreeUnstar(requireNodeId(args.positionals[2]), configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["trollbox", "history"]),
    usage: "regent trollbox history [--limit <n>] [--before <id>]",
    run: (args, configPath) => runTrollboxHistory(args, configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["trollbox", "post"]),
    usage: "regent trollbox post --body <text> [--reply-to <id>] [--client-message-id <id>]",
    run: (args, configPath) => runTrollboxPost(args, configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["trollbox", "tail"]),
    usage: "regent trollbox tail",
    run: (args, configPath) => runTrollboxTail(args, configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["gossipsub", "status"]),
    usage: "regent gossipsub status",
    run: (_args, configPath) => runGossipsubStatus(configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["xmtp", "init"]),
    usage: "regent xmtp init [--env local|dev|production] [--config <path>]",
    run: (args, configPath) => runXmtpInit(args, configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["xmtp", "info"]),
    usage: "regent xmtp info [--config <path>]",
    run: (_args, configPath) => runXmtpInfo(configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["xmtp", "status"]),
    usage: "regent xmtp status [--config <path>]",
    run: (_args, configPath) => runXmtpStatus(configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["xmtp", "resolve"]),
    usage: "regent xmtp resolve --address <wallet> [--config <path>]",
    run: (args, configPath) => runXmtpResolve(args, configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["xmtp", "owner", "add"]),
    usage: "regent xmtp owner add (--address <wallet> | --inbox-id <id>) [--config <path>]",
    run: (args, configPath) => runXmtpOwnerAdd(args, configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["xmtp", "policy", "init"]),
    usage: "regent xmtp policy init [--config <path>]",
    run: (_args, configPath) => runXmtpPolicyInit(configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["xmtp", "policy", "edit"]),
    usage: "regent xmtp policy edit [--config <path>]",
    run: (_args, configPath) => runXmtpPolicyEdit(configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["xmtp", "doctor"]),
    usage: "regent xmtp doctor [--json] [--verbose] [--fix] [--quiet] [--only-failures] [--ci] [--config <path>]",
    run: (args, configPath) => runXmtpDoctor(args, configPath),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "identities", "list"]),
    usage:
      "regent autolaunch identities list [--chain ethereum|sepolia|1|11155111] [--owner <address>] [--private-key <hex>] [--json]",
    run: (args) => runAutolaunchIdentitiesList(args),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "identities", "mint"]),
    usage:
      "regent autolaunch identities mint --chain ethereum|sepolia|1|11155111 [--agent-uri <uri>] [--rpc-url <url>] [--private-key <hex>] [--json]",
    run: (args) => runAutolaunchIdentitiesMint(args),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "agents", "list"]),
    usage: "regent autolaunch agents list [--launchable] [--json]",
    run: (args) => runAutolaunchAgentsList(args),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "agents", "show"]),
    usage: "regent autolaunch agents show <agent-id> [--json]",
    run: (args) => runAutolaunchAgentShow(requireArg(args.positionals[3], "agent-id")),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "agents", "readiness"]),
    usage: "regent autolaunch agents readiness <agent-id> [--json]",
    run: (args) => runAutolaunchAgentReadiness(requireArg(args.positionals[3], "agent-id")),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "ens", "plan"]),
    usage:
      "regent autolaunch ens plan --ens <name.eth> [--identity <chain:tokenId> | --chain-id <id> --agent-id <tokenId>] [--signer-address <address>] [--include-reverse] [--json]",
    run: (args) => runAutolaunchEnsPlan(args),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "ens", "prepare-ensip25"]),
    usage:
      "regent autolaunch ens prepare-ensip25 --ens <name.eth> [--identity <chain:tokenId> | --chain-id <id> --agent-id <tokenId>] [--signer-address <address>] [--json]",
    run: (args) => runAutolaunchEnsPrepareEnsip25(args),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "ens", "prepare-erc8004"]),
    usage:
      "regent autolaunch ens prepare-erc8004 --ens <name.eth> [--identity <chain:tokenId> | --chain-id <id> --agent-id <tokenId>] [--signer-address <address>] [--json]",
    run: (args) => runAutolaunchEnsPrepareErc8004(args),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "ens", "prepare-bidirectional"]),
    usage:
      "regent autolaunch ens prepare-bidirectional --ens <name.eth> [--identity <chain:tokenId> | --chain-id <id> --agent-id <tokenId>] [--signer-address <address>] [--include-reverse] [--json]",
    run: (args) => runAutolaunchEnsPrepareBidirectional(args),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "launch", "preview"]),
    usage:
      "regent autolaunch launch preview --agent <agent-id> --chain-id <id> --name <name> --symbol <symbol> --treasury-address <address> [--total-supply <value>] [--launch-notes <text>] [--json]",
    run: (args) => runAutolaunchLaunchPreview(args),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "launch", "create"]),
    usage:
      "regent autolaunch launch create --agent <agent-id> --chain-id <id> --name <name> --symbol <symbol> --treasury-address <address> --wallet-address <address> --nonce <nonce> --message <message> --signature <signature> --issued-at <iso> [--total-supply <value>] [--launch-notes <text>] [--json]",
    run: (args) => runAutolaunchLaunchCreate(args),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "jobs", "watch"]),
    usage: "regent autolaunch jobs watch <job-id> [--watch] [--interval <seconds>] [--json]",
    run: (args) => runAutolaunchJobsWatch(args),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "auctions", "list"]),
    usage:
      "regent autolaunch auctions list [--sort hottest|recently_launched|expired] [--status active|expired] [--chain <chain>] [--mine-only] [--json]",
    run: (args) => runAutolaunchAuctionsList(args),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "auctions", "show"]),
    usage: "regent autolaunch auctions show <auction-id> [--json]",
    run: (args) => runAutolaunchAuctionShow(requireArg(args.positionals[3], "auction-id")),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "bids", "quote"]),
    usage:
      "regent autolaunch bids quote --auction <auction-id> --amount <value> --max-price <value> [--json]",
    run: (args) => runAutolaunchBidsQuote(args),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "bids", "place"]),
    usage:
      "regent autolaunch bids place --auction <auction-id> --amount <value> --max-price <value> --tx-hash <hash> [--current-clearing-price <value>] [--projected-clearing-price <value>] [--estimated-tokens-if-end-now <value>] [--estimated-tokens-if-no-other-bids-change <value>] [--inactive-above-price <value>] [--status-band <value>] [--json]",
    run: (args) => runAutolaunchBidsPlace(args),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "bids", "mine"]),
    usage:
      "regent autolaunch bids mine [--auction <auction-id>] [--status active|borderline|inactive|claimable|exited|claimed] [--json]",
    run: (args) => runAutolaunchBidsMine(args),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "bids", "exit"]),
    usage: "regent autolaunch bids exit <bid-id> --tx-hash <hash> [--json]",
    run: (args) => runAutolaunchBidsExit(args),
  },
  {
    match: (args) => hasCommandPath(args, ["autolaunch", "bids", "claim"]),
    usage: "regent autolaunch bids claim <bid-id> --tx-hash <hash> [--json]",
    run: (args) => runAutolaunchBidsClaim(args),
  },
] as const;

const isEntrypoint = (): boolean => {
  const argvEntry = process.argv[1];
  if (!argvEntry) {
    return false;
  }

  const resolvedArgvEntry = path.resolve(argvEntry);
  const argvHref = pathToFileURL(resolvedArgvEntry).href;
  if (import.meta.url === argvHref) {
    return true;
  }

  if (fs.existsSync(resolvedArgvEntry)) {
    const realArgvHref = pathToFileURL(fs.realpathSync(resolvedArgvEntry)).href;
    if (import.meta.url === realArgvHref) {
      return true;
    }
  }

  const argvBasename = path.basename(resolvedArgvEntry);
  return argvBasename === "regent" || argvBasename === "regent.cmd";
};

if (isEntrypoint()) {
  void runCliEntrypoint().then((exitCode) => {
    process.exitCode = exitCode;
  });
}
