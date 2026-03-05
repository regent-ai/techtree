import { loadConfig } from "./config.js";
import { logger } from "./logger.js";
import {
  completeMembershipCommand,
  failMembershipCommand,
  leasePendingMembershipCommand,
} from "./membership.js";
import { mirrorMessage } from "./mirror.js";
import { ensureCanonicalRoom } from "./room.js";
import { runSyncLoop } from "./sync.js";
import { createIngestionTransport } from "./transport.js";
import type { CanonicalRoom, IngestionTransport, MembershipCommand } from "./types.js";

const config = loadConfig();

class ProcessedMembershipCommandCache {
  private readonly expiresAtByCommandId = new Map<string, number>();

  public constructor(private readonly ttlMs: number) {}

  public has(commandId: string, nowMs: number = Date.now()): boolean {
    this.prune(nowMs);

    const expiresAt = this.expiresAtByCommandId.get(commandId);
    return typeof expiresAt === "number" && expiresAt > nowMs;
  }

  public mark(commandId: string, nowMs: number = Date.now()): void {
    this.prune(nowMs);
    this.expiresAtByCommandId.set(commandId, nowMs + this.ttlMs);
  }

  private prune(nowMs: number): void {
    for (const [commandId, expiresAt] of this.expiresAtByCommandId) {
      if (expiresAt <= nowMs) {
        this.expiresAtByCommandId.delete(commandId);
      }
    }
  }
}

const processMembershipCommand = async (
  room: CanonicalRoom,
  command: MembershipCommand,
  transport: IngestionTransport,
  processedCache: ProcessedMembershipCommandCache,
): Promise<void> => {
  if (processedCache.has(command.id)) {
    try {
      await completeMembershipCommand(command.id);
      logger.warn("duplicate membership command lease completed idempotently", {
        commandId: command.id,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error("failed to complete duplicate membership command", {
        commandId: command.id,
        message,
      });
    }

    return;
  }

  try {
    logger.info("processing membership command", {
      commandId: command.id,
      op: command.op,
      transportMode: transport.mode,
      transport: transport.name,
    });

    const result = await transport.applyMembershipCommand({ room, command });
    await completeMembershipCommand(command.id);
    processedCache.mark(command.id);

    logger.info("membership command completed", {
      commandId: command.id,
      op: command.op,
      inboxId: command.inboxId,
      result,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);

    try {
      await failMembershipCommand(command.id, message);
    } catch (failError) {
      const failMessage = failError instanceof Error ? failError.message : String(failError);
      logger.error("failed to mark membership command failure", {
        commandId: command.id,
        message: failMessage,
      });
    }

    logger.error("membership command failed", {
      commandId: command.id,
      message,
    });
  }
};

const drainMembershipCommands = async (
  room: CanonicalRoom,
  transport: IngestionTransport,
  processedCache: ProcessedMembershipCommandCache,
): Promise<void> => {
  let leased = 0;

  while (leased < config.membershipLeaseBatchSize) {
    const command = await leasePendingMembershipCommand();
    if (!command) {
      break;
    }

    leased += 1;
    await processMembershipCommand(room, command, transport, processedCache);
  }

  if (leased === config.membershipLeaseBatchSize) {
    logger.warn("membership lease batch limit reached", {
      batchSize: config.membershipLeaseBatchSize,
    });
  }
};

const controller = new AbortController();
process.on("SIGINT", () => controller.abort());
process.on("SIGTERM", () => controller.abort());

const transport = await createIngestionTransport({ config, logger });
const canonicalGroupId =
  typeof transport.getCanonicalGroupId === "function"
    ? await transport.getCanonicalGroupId()
    : null;
const room = await ensureCanonicalRoom(config.canonicalRoomKey, canonicalGroupId);
const processedMembershipCommands = new ProcessedMembershipCommandCache(
  config.membershipCommandCacheTtlMs,
);

logger.info("canonical room ready", {
  room,
  transportMode: transport.mode,
  transport: transport.name,
  canonicalGroupId: canonicalGroupId ?? room.xmtpGroupId,
});

await runSyncLoop({
  signal: controller.signal,
  stream: transport.createEventStream({
    signal: controller.signal,
    pollIntervalMs: config.pollIntervalMs,
  }),
  onEvent: async (event) => {
    if (event.kind === "message") {
      const result = await mirrorMessage(event);
      logger.info("mirrored message", {
        messageId: event.id,
        mirroredId: result.mirroredId,
        deduped: result.deduped === true,
      });
    }

    await drainMembershipCommands(room, transport, processedMembershipCommands);

    if (event.kind === "heartbeat") {
      logger.info("heartbeat", {
        id: event.id,
        source: event.source,
      });
    }
  },
  onError: async (error) => {
    const message = error instanceof Error ? error.message : String(error);
    logger.error("sync loop crashed", { message });
    process.exitCode = 1;
  },
});
