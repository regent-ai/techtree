import fs from "node:fs";
import net from "node:net";

import type { NodeCreateInput, WatchedNodeLiveEvent } from "@regent/types";
import { resolveWatchedNodeRelaySocketPath } from "@regent/runtime";

import { daemonCall } from "../daemon-client.js";
import { getFlag, parseIntegerFlag, requireArg, type ParsedCliArgs } from "../parse.js";
import { printJson } from "../printer.js";

const readAtPathValue = (value: string): string => {
  if (!value.startsWith("@")) {
    return value;
  }

  return fs.readFileSync(value.slice(1), "utf8");
};

const assertSkillTriplet = (input: {
  skillSlug?: string;
  skillVersion?: string;
  skillMdBody?: string;
}): void => {
  const present = [input.skillSlug, input.skillVersion, input.skillMdBody].filter(
    (value) => value !== undefined,
  ).length;

  if (present !== 0 && present !== 3) {
    throw new Error(
      "skill node inputs must include --skill-slug, --skill-version, and --skill-md together",
    );
  }
};

type NodeCreateSidelinkInput = NonNullable<NodeCreateInput["sidelinks"]>[number];

const collectRepeatedFlagValues = (args: ParsedCliArgs, name: string): string[] => {
  const values: string[] = [];

  for (let index = 0; index < args.raw.length; index += 1) {
    const current = args.raw[index];
    if (!current) {
      continue;
    }

    if (current === "--") {
      break;
    }

    if (current === `--${name}`) {
      const next = args.raw[index + 1];
      if (!next || next.startsWith("--")) {
        throw new Error(`missing required value for --${name}`);
      }

      values.push(next);
      index += 1;
      continue;
    }

    if (current.startsWith(`--${name}=`)) {
      values.push(current.slice(name.length + 3));
    }
  }

  return values;
};

const parseRequiredIntegerLiteral = (value: string, label: string): number => {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw new Error(`invalid integer for ${label}`);
  }

  return parsed;
};

const parseSidelinkValue = (value: string): NodeCreateSidelinkInput => {
  const [rawNodeId, rawTag, rawOrdinal, ...extra] = value.split(":");
  if (!rawNodeId || extra.length > 0) {
    throw new Error("invalid sidelink; expected --sidelink <node-id>[:tag[:ordinal]]");
  }

  const tag = rawTag?.trim();
  const ordinal =
    rawOrdinal === undefined || rawOrdinal === ""
      ? undefined
      : parseRequiredIntegerLiteral(rawOrdinal, "--sidelink ordinal");

  return {
    node_id: parseRequiredIntegerLiteral(rawNodeId, "--sidelink node id"),
    ...(tag ? { tag } : {}),
    ...(ordinal === undefined ? {} : { ordinal }),
  };
};

export async function runTechtreeStatus(configPath?: string): Promise<void> {
  printJson(await daemonCall("techtree.status", undefined, configPath));
}

export async function runTechtreeNodesList(args: ParsedCliArgs, configPath?: string): Promise<void> {
  printJson(
    await daemonCall(
      "techtree.nodes.list",
      {
        limit: parseIntegerFlag(args, "limit"),
        seed: getFlag(args, "seed"),
      },
      configPath,
    ),
  );
}

export async function runTechtreeNodeGet(id: number, configPath?: string): Promise<void> {
  printJson(await daemonCall("techtree.nodes.get", { id }, configPath));
}

export async function runTechtreeNodeChildren(args: ParsedCliArgs, id: number, configPath?: string): Promise<void> {
  printJson(
    await daemonCall(
      "techtree.nodes.children",
      {
        id,
        limit: parseIntegerFlag(args, "limit"),
      },
      configPath,
    ),
  );
}

export async function runTechtreeNodeComments(args: ParsedCliArgs, id: number, configPath?: string): Promise<void> {
  printJson(
    await daemonCall(
      "techtree.nodes.comments",
      {
        id,
        limit: parseIntegerFlag(args, "limit"),
      },
      configPath,
    ),
  );
}

export async function runTechtreeActivity(args: ParsedCliArgs, configPath?: string): Promise<void> {
  printJson(
    await daemonCall(
      "techtree.activity.list",
      {
        limit: parseIntegerFlag(args, "limit"),
      },
      configPath,
    ),
  );
}

export async function runTechtreeSearch(args: ParsedCliArgs, configPath?: string): Promise<void> {
  printJson(
    await daemonCall(
      "techtree.search.query",
      {
        q: requireArg(getFlag(args, "query"), "query"),
        limit: parseIntegerFlag(args, "limit"),
      },
      configPath,
    ),
  );
}

export async function runTechtreeNodeWorkPacket(id: number, configPath?: string): Promise<void> {
  printJson(await daemonCall("techtree.nodes.workPacket", { id }, configPath));
}

export async function runTechtreeNodeCreate(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const skillSlug = getFlag(args, "skill-slug");
  const skillVersion = getFlag(args, "skill-version");
  const skillMdFlag = getFlag(args, "skill-md");
  const skillMdBody = skillMdFlag ? readAtPathValue(skillMdFlag) : undefined;
  const sidelinks = collectRepeatedFlagValues(args, "sidelink").map(parseSidelinkValue);

  assertSkillTriplet({ skillSlug, skillVersion, skillMdBody });

  const notebookFlag = requireArg(getFlag(args, "notebook-source"), "notebook-source");
  const payload: NodeCreateInput = {
    seed: requireArg(getFlag(args, "seed"), "seed"),
    kind: requireArg(getFlag(args, "kind"), "kind") as NodeCreateInput["kind"],
    title: requireArg(getFlag(args, "title"), "title"),
    parent_id: requireInteger(parseIntegerFlag(args, "parent-id"), "parent-id"),
    notebook_source: readAtPathValue(notebookFlag),
    ...(sidelinks.length === 0 ? {} : { sidelinks }),
    slug: getFlag(args, "slug"),
    summary: getFlag(args, "summary"),
    skill_slug: skillSlug,
    skill_version: skillVersion,
    skill_md_body: skillMdBody,
    idempotency_key: getFlag(args, "idempotency-key"),
  };

  printJson(await daemonCall("techtree.nodes.create", payload, configPath));
}

export async function runTechtreeCommentAdd(args: ParsedCliArgs, configPath?: string): Promise<void> {
  printJson(
    await daemonCall(
      "techtree.comments.create",
      {
        node_id: requireInteger(parseIntegerFlag(args, "node-id"), "node-id"),
        body_markdown: requireArg(getFlag(args, "body-markdown"), "body-markdown"),
        body_plaintext: getFlag(args, "body-plaintext"),
        idempotency_key: getFlag(args, "idempotency-key"),
      },
      configPath,
    ),
  );
}

export async function runTechtreeWatch(nodeId: number, configPath?: string): Promise<void> {
  printJson(await daemonCall("techtree.watch.create", { nodeId }, configPath));
}

export async function runTechtreeUnwatch(nodeId: number, configPath?: string): Promise<void> {
  printJson(await daemonCall("techtree.watch.delete", { nodeId }, configPath));
}

export async function runTechtreeWatchList(configPath?: string): Promise<void> {
  printJson(await daemonCall("techtree.watch.list", undefined, configPath));
}

const isWatchedNodeLiveEvent = (payload: unknown): payload is WatchedNodeLiveEvent => {
  if (!payload || typeof payload !== "object") {
    return false;
  }

  const candidate = payload as Partial<WatchedNodeLiveEvent>;
  return !!candidate.event && !!candidate.data && typeof candidate.event === "object" && typeof candidate.data === "object";
};

export async function runTechtreeWatchTail(configPath?: string): Promise<void> {
  const runtimeStatus = await daemonCall("runtime.status", undefined, configPath);
  const eventSocketPath = resolveWatchedNodeRelaySocketPath(runtimeStatus.socketPath);

  await new Promise<void>((resolve, reject) => {
    const socket = net.createConnection(eventSocketPath);
    let buffer = "";

    const cleanup = () => {
      process.off("SIGINT", handleSignal);
      process.off("SIGTERM", handleSignal);
      socket.removeAllListeners();
      socket.end();
      socket.destroy();
    };

    const handleSignal = () => {
      cleanup();
      resolve();
    };

    process.on("SIGINT", handleSignal);
    process.on("SIGTERM", handleSignal);

    socket.setEncoding("utf8");
    socket.on("data", (chunk) => {
      buffer += chunk;

      while (true) {
        const newlineIndex = buffer.indexOf("\n");
        if (newlineIndex < 0) {
          break;
        }

        const line = buffer.slice(0, newlineIndex).trim();
        buffer = buffer.slice(newlineIndex + 1);

        if (!line) {
          continue;
        }

        let payload: unknown;

        try {
          payload = JSON.parse(line) as unknown;
        } catch {
          cleanup();
          reject(new Error("runtime watch relay returned invalid JSON"));
          return;
        }

        if (isWatchedNodeLiveEvent(payload)) {
          printJson(payload);
          continue;
        }

        if (payload && typeof payload === "object" && "error" in payload) {
          cleanup();
          reject(
            new Error(
              `runtime watch relay error: ${String((payload as { error?: unknown }).error ?? "unknown")}`,
            ),
          );
          return;
        }
      }
    });

    socket.on("error", () => {
      cleanup();
      reject(new Error(`unable to connect to local watch relay at ${eventSocketPath}`));
    });

    socket.on("close", () => {
      cleanup();
      resolve();
    });
  });
}

export async function runTechtreeStar(nodeId: number, configPath?: string): Promise<void> {
  printJson(await daemonCall("techtree.stars.create", { nodeId }, configPath));
}

export async function runTechtreeUnstar(nodeId: number, configPath?: string): Promise<void> {
  printJson(await daemonCall("techtree.stars.delete", { nodeId }, configPath));
}

export async function runTechtreeInbox(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const kind = getFlag(args, "kind");
  printJson(
    await daemonCall(
      "techtree.inbox.get",
      {
        cursor: parseIntegerFlag(args, "cursor"),
        limit: parseIntegerFlag(args, "limit"),
        seed: getFlag(args, "seed"),
        kind: kind ? kind.split(",").map((value) => value.trim()).filter(Boolean) : undefined,
      },
      configPath,
    ),
  );
}

export async function runTechtreeOpportunities(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const kind = getFlag(args, "kind");
  const limit = parseIntegerFlag(args, "limit");
  const seed = getFlag(args, "seed");
  const params = {
    ...(limit !== undefined ? { limit } : {}),
    ...(seed ? { seed } : {}),
    ...(kind ? { kind: kind.split(",").map((value) => value.trim()).filter(Boolean) } : {}),
  };

  printJson(
    await daemonCall(
      "techtree.opportunities.list",
      params,
      configPath,
    ),
  );
}

const requireInteger = (value: number | undefined, name: string): number => {
  if (value === undefined) {
    throw new Error(`missing required argument: --${name}`);
  }

  return value;
};
