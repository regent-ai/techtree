#!/usr/bin/env node
import path from "node:path";
import { fileURLToPath } from "node:url";

import { defaultConfigPath, expandHome } from "@regent/runtime";

import { runAgentbookLookup, runAgentbookRegister, runAgentbookSessionsWatch, runAgentbookVerifyHeader } from "./commands/agentbook.js";
import {
  runAutolaunchAgentsList,
  runAutolaunchAgentReadiness,
  runAutolaunchAgentShow,
  runAutolaunchAuctionsList,
  runAutolaunchAuctionShow,
  runAutolaunchBidsClaim,
  runAutolaunchBidsExit,
  runAutolaunchBidsMine,
  runAutolaunchBidsPlace,
  runAutolaunchBidsQuote,
  runAutolaunchEnsPlan,
  runAutolaunchEnsPrepareBidirectional,
  runAutolaunchEnsPrepareErc8004,
  runAutolaunchEnsPrepareEnsip25,
  runAutolaunchIdentitiesList,
  runAutolaunchIdentitiesMint,
  runAutolaunchJobsWatch,
  runAutolaunchLaunchCreate,
  runAutolaunchLaunchPreview,
} from "./commands/autolaunch.js";
import {
  runBbhLeaderboard,
  runBbhRun,
  runBbhSubmit,
  runBbhSync,
  runBbhValidate,
} from "./commands/bbh.js";
import { runConfigRead, runConfigWrite } from "./commands/config.js";
import { runDoctorCommand } from "./commands/doctor.js";
import { runAuthSiwaLogin, runAuthSiwaLogout, runAuthSiwaStatus } from "./commands/auth.js";
import { runCreateInit, runCreateWallet } from "./commands/create.js";
import { runGossipsubStatus } from "./commands/gossipsub.js";
import { runRuntime } from "./commands/run.js";
import {
  runTechtreeActivity,
  runTechtreeInbox,
  runTechtreeNodeChildren,
  runTechtreeNodeComments,
  runTechtreeNodeGet,
  runTechtreeNodeWorkPacket,
  runTechtreeNodesList,
  runTechtreeOpportunities,
  runTechtreeSearch,
  runTechtreeStar,
  runTechtreeStatus,
  runTechtreeUnstar,
  runTechtreeUnwatch,
  runTechtreeWatch,
  runTechtreeWatchList,
  runTechtreeWatchTail,
} from "./commands/techtree.js";
import {
  runTechtreeArtifactCompile,
  runTechtreeArtifactInit,
  runTechtreeArtifactPin,
  runTechtreeArtifactPublish,
  runTechtreeFetch,
  runTechtreeReviewCompile,
  runTechtreeReviewInit,
  runTechtreeReviewPin,
  runTechtreeReviewPublish,
  runTechtreeRunCompile,
  runTechtreeRunExec,
  runTechtreeRunInit,
  runTechtreeRunPin,
  runTechtreeRunPublish,
  runTechtreeVerify,
} from "./commands/techtree-v1.js";
import {
  runXmtpDoctor,
  runXmtpGroupAddMember,
  runXmtpGroupCreate,
  runXmtpGroupList,
  runXmtpInfo,
  runXmtpInit,
  runXmtpOwnerAdd,
  runXmtpOwnerList,
  runXmtpOwnerRemove,
  runXmtpPolicyInit,
  runXmtpPolicyShow,
  runXmtpPolicyValidate,
  runXmtpPolicyEdit,
  runXmtpRevokeOtherInstallations,
  runXmtpResolve,
  runXmtpStatus,
  runXmtpRotateDbKey,
  runXmtpRotateWallet,
  runXmtpTestDm,
  runXmtpTrustedAdd,
  runXmtpTrustedList,
  runXmtpTrustedRemove,
} from "./commands/xmtp.js";
import { getFlag, parseCliArgs } from "./parse.js";
import { printError, printJson } from "./printer.js";

export const parseConfigPath = (args: string[]): string | undefined => {
  const configFlag = getFlag(args, "config");
  return configFlag ? expandHome(configFlag) : undefined;
};

export const positionalCliArgs = (args: string[]): string[] => {
  const result: string[] = [];

  for (let index = 0; index < args.length; index += 1) {
    const value = args[index];
    if (!value) {
      continue;
    }

    if (value === "--config") {
      index += 1;
      continue;
    }

    if (value.startsWith("--config=")) {
      continue;
    }

    if (value.startsWith("--")) {
      const next = args[index + 1];
      if (next && !next.startsWith("--")) {
        index += 1;
      }
      continue;
    }

    result.push(value);
  }

  return result;
};

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

const usage = (configPath?: string): void => {
  printJson({
    usage: [
      "regent run",
      "regent create init",
      "regent create wallet",
      "regent auth siwa login",
      "regent auth siwa status",
      "regent auth siwa logout",
      "regent config read",
      "regent config write",
      "regent doctor",
      "regent techtree status",
      "regent techtree activity",
      "regent techtree search",
      "regent techtree nodes list",
      "regent techtree node get <id>",
      "regent techtree node children <id>",
      "regent techtree node comments <id>",
      "regent techtree node work-packet <id>",
      "regent techtree watch list",
      "regent techtree watch tail",
      "regent techtree watch <id>",
      "regent techtree unwatch <id>",
      "regent techtree star <id>",
      "regent techtree unstar <id>",
      "regent techtree inbox",
      "regent techtree opportunities",
      "regent techtree artifact init [path]",
      "regent techtree artifact compile [path]",
      "regent techtree artifact pin [path]",
      "regent techtree artifact publish [path]",
      "regent techtree run init --artifact <id> [path]",
      "regent techtree run exec [path]",
      "regent techtree run compile [path]",
      "regent techtree run pin [path]",
      "regent techtree run publish [path]",
      "regent techtree review init --target <id> [path]",
      "regent techtree review compile [path]",
      "regent techtree review pin [path]",
      "regent techtree review publish [path]",
      "regent techtree fetch <id>",
      "regent techtree verify <id>",
      "regent xmtp init",
      "regent xmtp info",
      "regent xmtp status",
      "regent xmtp resolve",
      "regent xmtp owner add",
      "regent xmtp owner list",
      "regent xmtp owner remove",
      "regent xmtp trusted add",
      "regent xmtp trusted list",
      "regent xmtp trusted remove",
      "regent xmtp policy init",
      "regent xmtp policy show",
      "regent xmtp policy validate",
      "regent xmtp policy edit",
      "regent xmtp test dm",
      "regent xmtp group create",
      "regent xmtp group add-member",
      "regent xmtp group list",
      "regent xmtp revoke-other-installations",
      "regent xmtp rotate-db-key",
      "regent xmtp rotate-wallet",
      "regent xmtp doctor",
      "regent bbh run",
      "regent bbh submit",
      "regent bbh validate",
      "regent bbh sync",
      "regent bbh leaderboard",
      "regent autolaunch ...",
      "regent agentbook ...",
      "regent gossipsub status",
      `default config: ${configPath ?? defaultConfigPath()}`,
    ],
  });
};

export async function runCliEntrypoint(rawArgs: string[]): Promise<number> {
  try {
    const parsedArgs = parseCliArgs(rawArgs);
    const args = positionalCliArgs(rawArgs);
    const configPath = parseConfigPath(rawArgs);
    const [namespace, subcommand, maybeThird, maybeFourth] = args;

    if (namespace === "run") {
      await runRuntime(configPath);
      return 0;
    }

    if (namespace === "create" && subcommand === "init") {
      await runCreateInit(rawArgs);
      return 0;
    }

    if (namespace === "create" && subcommand === "wallet") {
      await runCreateWallet(rawArgs);
      return 0;
    }

    if (namespace === "config" && subcommand === "read") {
      await runConfigRead(parsedArgs);
      return 0;
    }

    if (namespace === "config" && subcommand === "write") {
      await runConfigWrite(parsedArgs);
      return 0;
    }

    if (namespace === "doctor") {
      return await runDoctorCommand(parsedArgs, configPath);
    }

    if (namespace === "auth" && subcommand === "siwa" && maybeThird === "login") {
      await runAuthSiwaLogin(rawArgs, configPath);
      return 0;
    }

    if (namespace === "auth" && subcommand === "siwa" && maybeThird === "status") {
      await runAuthSiwaStatus(configPath);
      return 0;
    }

    if (namespace === "auth" && subcommand === "siwa" && maybeThird === "logout") {
      await runAuthSiwaLogout(configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "status") {
      await runTechtreeStatus(configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "activity") {
      await runTechtreeActivity(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "search") {
      await runTechtreeSearch(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "nodes" && maybeThird === "list") {
      await runTechtreeNodesList(rawArgs, configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "node" && maybeThird === "get") {
      await runTechtreeNodeGet(requireNodeId(maybeFourth), configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "node" && maybeThird === "children") {
      await runTechtreeNodeChildren(rawArgs, requireNodeId(maybeFourth), configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "node" && maybeThird === "comments") {
      await runTechtreeNodeComments(rawArgs, requireNodeId(maybeFourth), configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "node" && maybeThird === "work-packet") {
      await runTechtreeNodeWorkPacket(requireNodeId(maybeFourth), configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "artifact" && maybeThird === "init") {
      await runTechtreeArtifactInit(parsedArgs);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "artifact" && maybeThird === "compile") {
      await runTechtreeArtifactCompile(parsedArgs);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "artifact" && maybeThird === "pin") {
      await runTechtreeArtifactPin(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "artifact" && maybeThird === "publish") {
      await runTechtreeArtifactPublish(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "run" && maybeThird === "init") {
      await runTechtreeRunInit(parsedArgs);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "run" && maybeThird === "exec") {
      await runTechtreeRunExec(parsedArgs);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "run" && maybeThird === "compile") {
      await runTechtreeRunCompile(parsedArgs);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "run" && maybeThird === "pin") {
      await runTechtreeRunPin(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "run" && maybeThird === "publish") {
      await runTechtreeRunPublish(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "review" && maybeThird === "init") {
      await runTechtreeReviewInit(parsedArgs);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "review" && maybeThird === "compile") {
      await runTechtreeReviewCompile(parsedArgs);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "review" && maybeThird === "pin") {
      await runTechtreeReviewPin(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "review" && maybeThird === "publish") {
      await runTechtreeReviewPublish(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "fetch") {
      await runTechtreeFetch(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "verify") {
      await runTechtreeVerify(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "watch" && maybeThird === "list") {
      await runTechtreeWatchList(configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "watch" && maybeThird === "tail") {
      await runTechtreeWatchTail(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "watch") {
      await runTechtreeWatch(requireNodeId(maybeThird), configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "unwatch") {
      await runTechtreeUnwatch(requireNodeId(maybeThird), configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "star") {
      await runTechtreeStar(requireNodeId(maybeThird), configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "unstar") {
      await runTechtreeUnstar(requireNodeId(maybeThird), configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "inbox") {
      await runTechtreeInbox(rawArgs, configPath);
      return 0;
    }

    if (namespace === "techtree" && subcommand === "opportunities") {
      await runTechtreeOpportunities(rawArgs, configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "init") {
      return await runXmtpInit(parsedArgs, configPath);
    }

    if (namespace === "xmtp" && subcommand === "info") {
      await runXmtpInfo(configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "status") {
      await runXmtpStatus(configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "resolve") {
      await runXmtpResolve(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "owner" && maybeThird === "add") {
      await runXmtpOwnerAdd(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "owner" && maybeThird === "list") {
      await runXmtpOwnerList(configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "owner" && maybeThird === "remove") {
      await runXmtpOwnerRemove(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "trusted" && maybeThird === "add") {
      await runXmtpTrustedAdd(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "trusted" && maybeThird === "list") {
      await runXmtpTrustedList(configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "trusted" && maybeThird === "remove") {
      await runXmtpTrustedRemove(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "policy" && maybeThird === "init") {
      await runXmtpPolicyInit(configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "policy" && maybeThird === "show") {
      await runXmtpPolicyShow(configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "policy" && maybeThird === "validate") {
      return await runXmtpPolicyValidate(configPath);
    }

    if (namespace === "xmtp" && subcommand === "policy" && maybeThird === "edit") {
      await runXmtpPolicyEdit(configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "test" && maybeThird === "dm") {
      await runXmtpTestDm(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "group" && maybeThird === "create") {
      await runXmtpGroupCreate(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "group" && maybeThird === "add-member") {
      await runXmtpGroupAddMember(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "group" && maybeThird === "list") {
      await runXmtpGroupList(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "revoke-other-installations") {
      await runXmtpRevokeOtherInstallations(configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "rotate-db-key") {
      await runXmtpRotateDbKey(configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "rotate-wallet") {
      await runXmtpRotateWallet(configPath);
      return 0;
    }

    if (namespace === "xmtp" && subcommand === "doctor") {
      return await runXmtpDoctor(parsedArgs, configPath);
    }

    if (namespace === "agentbook" && subcommand === "register") {
      await runAgentbookRegister(parsedArgs);
      return 0;
    }

    if (namespace === "agentbook" && subcommand === "sessions" && maybeThird === "watch") {
      await runAgentbookSessionsWatch(parsedArgs);
      return 0;
    }

    if (namespace === "agentbook" && subcommand === "lookup") {
      await runAgentbookLookup(parsedArgs);
      return 0;
    }

    if (namespace === "agentbook" && subcommand === "verify-header") {
      await runAgentbookVerifyHeader(parsedArgs);
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "agents" && maybeThird === "list") {
      await runAutolaunchAgentsList(parsedArgs);
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "agent" && maybeThird === "readiness") {
      await runAutolaunchAgentReadiness(requireNodeId(maybeFourth).toString());
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "agent" && maybeThird) {
      await runAutolaunchAgentShow(maybeThird);
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "auctions" && maybeThird === "list") {
      await runAutolaunchAuctionsList(parsedArgs);
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "auction" && maybeThird) {
      await runAutolaunchAuctionShow(maybeThird);
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "bids" && maybeThird === "quote") {
      await runAutolaunchBidsQuote(parsedArgs);
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "bids" && maybeThird === "place") {
      await runAutolaunchBidsPlace(parsedArgs);
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "bids" && maybeThird === "mine") {
      await runAutolaunchBidsMine(parsedArgs);
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "bids" && maybeThird === "exit") {
      await runAutolaunchBidsExit(parsedArgs);
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "bids" && maybeThird === "claim") {
      await runAutolaunchBidsClaim(parsedArgs);
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "ens" && maybeThird === "plan") {
      await runAutolaunchEnsPlan(parsedArgs);
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "ens" && maybeThird === "prepare-ensip25") {
      await runAutolaunchEnsPrepareEnsip25(parsedArgs);
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "ens" && maybeThird === "prepare-erc8004") {
      await runAutolaunchEnsPrepareErc8004(parsedArgs);
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "ens" && maybeThird === "prepare-bidirectional") {
      await runAutolaunchEnsPrepareBidirectional(parsedArgs);
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "identities" && maybeThird === "list") {
      await runAutolaunchIdentitiesList(parsedArgs);
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "identities" && maybeThird === "mint") {
      await runAutolaunchIdentitiesMint(parsedArgs);
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "launch" && maybeThird === "preview") {
      await runAutolaunchLaunchPreview(parsedArgs);
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "launch" && maybeThird === "create") {
      await runAutolaunchLaunchCreate(parsedArgs);
      return 0;
    }

    if (namespace === "autolaunch" && subcommand === "jobs" && maybeThird === "watch") {
      await runAutolaunchJobsWatch(parsedArgs);
      return 0;
    }

    if (namespace === "gossipsub" && subcommand === "status") {
      await runGossipsubStatus(configPath);
      return 0;
    }

    if (namespace === "bbh" && subcommand === "run") {
      await runBbhRun(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "bbh" && subcommand === "submit") {
      await runBbhSubmit(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "bbh" && subcommand === "validate") {
      await runBbhValidate(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "bbh" && subcommand === "sync") {
      await runBbhSync(parsedArgs, configPath);
      return 0;
    }

    if (namespace === "bbh" && subcommand === "leaderboard") {
      await runBbhLeaderboard(parsedArgs, configPath);
      return 0;
    }

    usage(configPath);
    return 0;
  } catch (error) {
    printError(error);
    return 1;
  }
}

export async function runCli(rawArgs: string[] = process.argv.slice(2)): Promise<number | void> {
  return runCliEntrypoint(rawArgs);
}

const main = async (): Promise<void> => {
  const exitCode = await runCliEntrypoint(process.argv.slice(2));
  if (exitCode !== 0) {
    process.exitCode = exitCode;
  }
};

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  void main();
}
