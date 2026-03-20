import net from "node:net";

import type { GossipsubStatus, TrollboxLiveEvent } from "@regent/types";

import { daemonCall } from "../daemon-client.js";
import { getFlag, parseIntegerFlag, requireArg, type ParsedCliArgs } from "../parse.js";
import { printJson } from "../printer.js";

const isTrollboxLiveEvent = (payload: unknown): payload is TrollboxLiveEvent => {
  if (!payload || typeof payload !== "object") {
    return false;
  }

  const candidate = payload as Partial<TrollboxLiveEvent>;
  return typeof candidate.event === "string" && !!candidate.message && typeof candidate.message === "object";
};

export async function runTrollboxHistory(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const room = getFlag(args, "room");
  printJson(
    await daemonCall(
      "techtree.trollbox.history",
      {
        limit: parseIntegerFlag(args, "limit"),
        before: parseIntegerFlag(args, "before"),
        room: room === "agent" ? "agent" : undefined,
      },
      configPath,
    ),
  );
}

export async function runTrollboxPost(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const room = getFlag(args, "room");
  printJson(
    await daemonCall(
      "techtree.trollbox.post",
      {
        body: requireArg(getFlag(args, "body"), "body"),
        reply_to_message_id: parseIntegerFlag(args, "reply-to"),
        client_message_id: getFlag(args, "client-message-id"),
        room: room === "agent" ? "agent" : undefined,
      },
      configPath,
    ),
  );
}

export async function runTrollboxTail(args?: ParsedCliArgs, configPath?: string): Promise<void> {
  const room = args && getFlag(args, "room") === "agent" ? "agent" : "global";
  const status = await daemonCall("gossipsub.status", undefined, configPath);

  if (!status.enabled) {
    throw new Error("trollbox transport is disabled in config");
  }

  if (!status.eventSocketPath) {
    throw new Error("runtime did not expose a local trollbox transport socket");
  }

  const eventSocketPath = status.eventSocketPath;

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
    socket.on("connect", () => {
      socket.write(`${JSON.stringify({ room })}\n`);
    });
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
          reject(new Error("runtime trollbox transport stream returned invalid JSON"));
          return;
        }

        if (isTrollboxLiveEvent(payload)) {
          printJson(payload);
          continue;
        }

        if (payload && typeof payload === "object" && "event" in payload && payload.event === "heartbeat") {
          continue;
        }

        if (payload && typeof payload === "object" && "error" in payload) {
          cleanup();
          reject(
            new Error(
              `runtime trollbox transport error: ${String((payload as { error?: unknown }).error ?? "unknown")}`,
            ),
          );
          return;
        }
      }
    });

    socket.on("error", () => {
      cleanup();
      reject(new Error(`unable to connect to local trollbox transport socket at ${eventSocketPath}`));
    });

    socket.on("close", () => {
      cleanup();
      resolve();
    });
  });
}
