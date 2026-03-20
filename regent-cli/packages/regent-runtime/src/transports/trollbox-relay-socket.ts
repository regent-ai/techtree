import fs from "node:fs";
import net from "node:net";
import path from "node:path";

import type { TrollboxLiveEvent } from "@regent/types";

import { ensureParentDir } from "../paths.js";
import type { GossipsubAdapter } from "./gossipsub-adapter.js";

export const resolveTrollboxRelaySocketPath = (runtimeSocketPath: string): string => {
  const parsed = path.parse(runtimeSocketPath);
  if (parsed.ext === ".sock") {
    return path.join(parsed.dir, `${parsed.name}.trollbox.sock`);
  }

  return path.join(path.dirname(runtimeSocketPath), `${path.basename(runtimeSocketPath)}.trollbox.sock`);
};

export class TrollboxRelaySocketServer {
  readonly socketPath: string;

  private readonly adapter: GossipsubAdapter;
  private server: net.Server | null = null;

  constructor(runtimeSocketPath: string, adapter: GossipsubAdapter) {
    this.socketPath = resolveTrollboxRelaySocketPath(runtimeSocketPath);
    this.adapter = adapter;
  }

  async start(): Promise<void> {
    if (this.server) {
      return;
    }

    ensureParentDir(this.socketPath);
    if (fs.existsSync(this.socketPath)) {
      fs.rmSync(this.socketPath, { force: true });
    }

    this.server = net.createServer((socket) => {
      socket.setEncoding("utf8");

      let unsubscribe: (() => void) | null = null;
      let buffer = "";
      let subscribed = false;

      const subscribe = (room: "global" | "agent") => {
        if (subscribed) {
          return;
        }

        subscribed = true;

        void this.adapter
          .subscribeTrollbox((event) => {
            socket.write(`${JSON.stringify(event)}\n`);
          }, room)
          .then((dispose) => {
            unsubscribe = dispose;
          })
          .catch((error: unknown) => {
            const message = error instanceof Error ? error.message : "unable to subscribe to trollbox relay";
            socket.write(`${JSON.stringify({ error: message })}\n`);
            socket.end();
          });
      };

      const cleanup = (): void => {
        if (!unsubscribe) {
          return;
        }

        const dispose = unsubscribe;
        unsubscribe = null;
        dispose();
      };

      socket.on("close", cleanup);
      socket.on("error", cleanup);
      socket.on("end", cleanup);
      socket.on("data", (chunk) => {
        buffer += chunk;

        while (true) {
          const newlineIndex = buffer.indexOf("\n");
          if (newlineIndex < 0) {
            break;
          }

          const line = buffer.slice(0, newlineIndex).trim();
          buffer = buffer.slice(newlineIndex + 1);

          if (line === "") {
            subscribe("global");
            continue;
          }

          try {
            const payload = JSON.parse(line) as { room?: unknown };
            subscribe(payload.room === "agent" ? "agent" : "global");
          } catch {
            subscribe("global");
          }
        }
      });

      setImmediate(() => subscribe("global"));
    });

    await new Promise<void>((resolve, reject) => {
      this.server?.once("error", reject);
      this.server?.listen(this.socketPath, () => {
        this.server?.off("error", reject);
        resolve();
      });
    });
  }

  async stop(): Promise<void> {
    const activeServer = this.server;
    this.server = null;

    if (activeServer) {
      await new Promise<void>((resolve, reject) => {
        activeServer.close((error) => {
          if (error) {
            reject(error);
            return;
          }

          resolve();
        });
      });
    }

    if (fs.existsSync(this.socketPath)) {
      fs.rmSync(this.socketPath, { force: true });
    }
  }
}
