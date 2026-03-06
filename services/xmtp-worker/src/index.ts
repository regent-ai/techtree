import { loadConfig } from "./config.js";
import { logger } from "./logger.js";
import { mirrorMessage } from "./mirror.js";
import { leaseMembershipCommand, listShardRooms, resolveMembershipCommand } from "./phoenix.js";
import { ensureCanonicalRoom } from "./room.js";
import { runSyncLoop } from "./sync.js";
import { createIngestionTransport } from "./transport.js";
import type { CanonicalRoom, IngestionTransport, MembershipCommand, TrollboxShard } from "./types.js";

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
      await resolveMembershipCommand(command.id, "done");
      logger.warn("duplicate membership command lease completed idempotently", {
        commandId: command.id,
        roomKey: room.roomKey,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error("failed to complete duplicate membership command", {
        commandId: command.id,
        roomKey: room.roomKey,
        message,
      });
    }

    return;
  }

  try {
    logger.info("processing membership command", {
      commandId: command.id,
      roomKey: room.roomKey,
      op: command.op,
      transportMode: transport.mode,
      transport: transport.name,
    });

    const result = await transport.applyMembershipCommand({ room, command });
    await resolveMembershipCommand(command.id, "done");
    processedCache.mark(command.id);

    logger.info("membership command completed", {
      commandId: command.id,
      roomKey: room.roomKey,
      op: command.op,
      inboxId: command.inboxId,
      result,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);

    try {
      await resolveMembershipCommand(command.id, "failed", message);
    } catch (failError) {
      const failMessage = failError instanceof Error ? failError.message : String(failError);
      logger.error("failed to mark membership command failure", {
        commandId: command.id,
        roomKey: room.roomKey,
        message: failMessage,
      });
    }

    logger.error("membership command failed", {
      commandId: command.id,
      roomKey: room.roomKey,
      message,
    });
  }
};

const normalizeShardRoom = (shard: TrollboxShard): CanonicalRoom => {
  return {
    roomKey: shard.roomKey,
    xmtpGroupId: shard.xmtpGroupId,
    name: shard.name,
    status: shard.status,
    ...(typeof shard.presenceTtlSeconds === "number"
      ? {presenceTtlSeconds: shard.presenceTtlSeconds}
      : {}),
  };
};

const buildRoomMap = (canonicalRoom: CanonicalRoom, shardRooms: readonly TrollboxShard[]): Map<string, CanonicalRoom> => {
  const map = new Map<string, CanonicalRoom>();

  map.set(canonicalRoom.roomKey, canonicalRoom);

  for (const shard of shardRooms) {
    const normalized = normalizeShardRoom(shard);
    map.set(normalized.roomKey, normalized);
  }

  if (!map.has(config.canonicalRoomKey)) {
    map.set(config.canonicalRoomKey, canonicalRoom);
  }

  return map;
};

const refreshShardRooms = async (
  canonicalRoom: CanonicalRoom,
  currentMap: Map<string, CanonicalRoom>,
): Promise<Map<string, CanonicalRoom>> => {
  try {
    const shardRooms = await listShardRooms();
    const nextMap = buildRoomMap(canonicalRoom, shardRooms);

    logger.info("refreshed shard room list", {
      shardCount: nextMap.size,
    });

    return nextMap;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    logger.warn("failed to refresh shard room list; keeping previous snapshot", { message });
    return currentMap;
  }
};

const drainMembershipCommands = async (
  roomsByKey: Map<string, CanonicalRoom>,
  transport: IngestionTransport,
  processedCache: ProcessedMembershipCommandCache,
): Promise<void> => {
  for (const room of roomsByKey.values()) {
    let leased = 0;

    while (leased < config.membershipLeaseBatchSize) {
      const command = await leaseMembershipCommand(room.roomKey);
      if (!command) {
        break;
      }

      leased += 1;
      await processMembershipCommand(room, command, transport, processedCache);
    }

    if (leased === config.membershipLeaseBatchSize) {
      logger.warn("membership lease batch limit reached", {
        roomKey: room.roomKey,
        batchSize: config.membershipLeaseBatchSize,
      });
    }
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
const canonicalRoom = await ensureCanonicalRoom(config.canonicalRoomKey, canonicalGroupId);
const processedMembershipCommands = new ProcessedMembershipCommandCache(
  config.membershipCommandCacheTtlMs,
);

let activeRoomsByKey = await refreshShardRooms(
  canonicalRoom,
  new Map<string, CanonicalRoom>([[canonicalRoom.roomKey, canonicalRoom]]),
);

logger.info("canonical room ready", {
  room: canonicalRoom,
  transportMode: transport.mode,
  transport: transport.name,
  canonicalGroupId: canonicalGroupId ?? canonicalRoom.xmtpGroupId,
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

    if (event.kind === "heartbeat") {
      activeRoomsByKey = await refreshShardRooms(canonicalRoom, activeRoomsByKey);
      logger.info("heartbeat", {
        id: event.id,
        source: event.source,
        shardCount: activeRoomsByKey.size,
      });
    }

    await drainMembershipCommands(activeRoomsByKey, transport, processedMembershipCommands);
  },
  onError: async (error) => {
    const message = error instanceof Error ? error.message : String(error);
    logger.error("sync loop crashed", { message });
    process.exitCode = 1;
  },
});
