import type { RegentConfig, XmtpStatus } from "@regent/types";

import { errorMessage } from "../errors.js";
import {
  getXmtpStatus,
  recordXmtpRecentConversation,
  recordXmtpRuntimeError,
  spawnXmtpCliProcess,
  syncXmtpConversations,
  updateXmtpRuntimeState,
} from "../xmtp/manager.js";

export interface XmtpAdapter {
  start(): Promise<void>;
  stop(): Promise<void>;
  status(): Promise<XmtpStatus>;
}

export class ManagedXmtpAdapter implements XmtpAdapter {
  private readonly config: RegentConfig["xmtp"];
  private started = false;
  private lastError: string | null = null;
  private stream: import("node:child_process").ChildProcessByStdio<
    null,
    import("node:stream").Readable,
    import("node:stream").Readable
  > | null = null;
  private restartTimer: ReturnType<typeof setTimeout> | null = null;
  private shuttingDown = false;

  constructor(config: RegentConfig["xmtp"]) {
    this.config = config;
  }

  async start(): Promise<void> {
    if (!this.config.enabled || this.started) {
      return;
    }

    this.started = true;
    this.shuttingDown = false;
    this.lastError = null;
    updateXmtpRuntimeState(this.config, (current) => ({
      ...current,
      connected: false,
      metrics: {
        ...current.metrics,
        startedAt: new Date().toISOString(),
        restarts: current.metrics.restarts + 1,
      },
    }));

    try {
      await syncXmtpConversations(this.config);
      this.launchStream();
    } catch (error) {
      this.lastError = errorMessage(error);
      recordXmtpRuntimeError(this.config, "xmtp_start_failed", this.lastError);
    }
  }

  async stop(): Promise<void> {
    this.shuttingDown = true;
    this.started = false;

    if (this.restartTimer) {
      clearTimeout(this.restartTimer);
      this.restartTimer = null;
    }

    if (this.stream) {
      this.stream.kill("SIGTERM");
      this.stream.removeAllListeners();
      this.stream.stdout.removeAllListeners();
      this.stream.stderr.removeAllListeners();
      this.stream = null;
    }

    updateXmtpRuntimeState(this.config, (current) => ({
      ...current,
      connected: false,
      metrics: {
        ...current.metrics,
        stoppedAt: new Date().toISOString(),
      },
    }));
  }

  async status(): Promise<XmtpStatus> {
    return getXmtpStatus(this.config, {
      started: this.started,
      lastError: this.lastError,
    });
  }

  private launchStream(): void {
    if (!this.started || this.shuttingDown) {
      return;
    }

    this.stream?.kill("SIGTERM");
    this.stream = spawnXmtpCliProcess(this.config, [
      "conversations",
      "stream-all-messages",
      "--json",
      "--disable-sync",
    ]);

    updateXmtpRuntimeState(this.config, (current) => ({
      ...current,
      connected: true,
    }));

    let stdoutBuffer = "";
    let stderrBuffer = "";

    this.stream.stdout.on("data", (chunk: Buffer | string) => {
      stdoutBuffer += chunk.toString();

      for (;;) {
        const newlineIndex = stdoutBuffer.indexOf("\n");
        if (newlineIndex < 0) {
          break;
        }

        const line = stdoutBuffer.slice(0, newlineIndex).trim();
        stdoutBuffer = stdoutBuffer.slice(newlineIndex + 1);
        if (!line) {
          continue;
        }

        try {
          const payload = JSON.parse(line) as {
            conversationId?: string;
            sentAt?: string;
          };
          const conversationId = payload.conversationId ?? "unknown";

          recordXmtpRecentConversation(this.config, {
            id: conversationId,
            type: "unknown",
            createdAt: payload.sentAt,
          });
          updateXmtpRuntimeState(this.config, (current) => ({
            ...current,
            connected: true,
            metrics: {
              ...current.metrics,
              lastMessageAt: payload.sentAt ?? new Date().toISOString(),
              receivedMessages: current.metrics.receivedMessages + 1,
            },
          }));
        } catch (error) {
          this.lastError = errorMessage(error);
          recordXmtpRuntimeError(this.config, "xmtp_stream_parse_error", this.lastError);
        }
      }
    });

    this.stream.stderr.on("data", (chunk: Buffer | string) => {
      stderrBuffer += chunk.toString();
    });

    this.stream.on("exit", (code, signal) => {
      this.stream = null;
      updateXmtpRuntimeState(this.config, (current) => ({
        ...current,
        connected: false,
      }));

      if (this.shuttingDown || !this.started) {
        return;
      }

      const reason = stderrBuffer.trim() || `XMTP stream exited with code ${String(code)} signal ${String(signal)}`;
      this.lastError = reason;
      recordXmtpRuntimeError(this.config, "xmtp_stream_exit", reason);
      this.restartTimer = setTimeout(() => {
        this.restartTimer = null;
        this.launchStream();
      }, 1_000);
    });

    this.stream.on("error", (error) => {
      this.lastError = errorMessage(error);
      recordXmtpRuntimeError(this.config, "xmtp_stream_error", this.lastError);
    });
  }
}
