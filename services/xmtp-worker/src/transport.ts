import { setTimeout as delay } from "node:timers/promises";

import type {
  CreateEventStreamOptions,
  IngestionEvent,
  IngestionTransport,
  MembershipApplyInput,
  MembershipApplyResult,
  RealTransportFactoryModule,
  WorkerConfig,
} from "./types.js";
import { createRealXmtpTransport } from "./real-transport.js";

interface TransportLogger {
  info(message: string, meta?: unknown): void;
  warn(message: string, meta?: unknown): void;
}

interface CreateTransportOptions {
  config: WorkerConfig;
  logger: TransportLogger;
}

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === "object" && value !== null;
};

const isFunction = (value: unknown): value is (...args: unknown[]) => unknown => {
  return typeof value === "function";
};

const isIngestionTransport = (value: unknown): value is IngestionTransport => {
  if (!isRecord(value)) {
    return false;
  }

  if (value.mode !== "mock" && value.mode !== "real") {
    return false;
  }

  return (
    typeof value.name === "string" &&
    value.name.length > 0 &&
    isFunction(value.createEventStream) &&
    isFunction(value.applyMembershipCommand)
  );
};

const toPaddedId = (prefix: string, sequence: number): string => {
  return `${prefix}-${String(sequence).padStart(8, "0")}`;
};

const toModuleSpecifier = (modulePath: string): string => {
  if (modulePath.startsWith(".") || modulePath.startsWith("/")) {
    return new URL(modulePath, `file://${process.cwd()}/`).href;
  }

  return modulePath;
};

class DeterministicMockTransport implements IngestionTransport {
  public readonly mode = "mock" as const;
  public readonly name = "deterministic-mock";

  private readonly membersByRoomKey = new Map<string, Set<string>>();
  private heartbeatSequence = 0;
  private messageSequence = 0;

  public constructor(private readonly config: WorkerConfig) {}

  public async *createEventStream(
    options: CreateEventStreamOptions,
  ): AsyncIterable<IngestionEvent> {
    while (!options.signal.aborted) {
      await delay(options.pollIntervalMs, undefined, { signal: options.signal }).catch(() => undefined);
      if (options.signal.aborted) {
        break;
      }

      this.heartbeatSequence += 1;

      if (
        this.config.mockMessageEveryHeartbeats > 0 &&
        this.heartbeatSequence % this.config.mockMessageEveryHeartbeats === 0
      ) {
        this.messageSequence += 1;

        yield {
          kind: "message",
          source: "xmtp",
          id: toPaddedId("mock-message", this.messageSequence),
          receivedAtMs: Date.now(),
          payload: {
            topic: this.config.canonicalRoomKey,
            sender: `mock-inbox-${(this.messageSequence % 3) + 1}`,
            body: `mock message ${this.messageSequence}`,
          },
        };
      }

      yield {
        kind: "heartbeat",
        source: "xmtp",
        id: toPaddedId("mock-heartbeat", this.heartbeatSequence),
        receivedAtMs: Date.now(),
        payload: { lagMs: 0 },
      };
    }
  }

  public async applyMembershipCommand(input: MembershipApplyInput): Promise<MembershipApplyResult> {
    if (!input.room.xmtpGroupId || input.room.xmtpGroupId.length === 0) {
      throw new Error("canonical room missing xmtp_group_id");
    }

    const existing = this.membersByRoomKey.get(input.room.roomKey);
    const members = existing ?? new Set<string>();

    this.membersByRoomKey.set(input.room.roomKey, members);

    if (input.command.op === "add_member") {
      if (members.has(input.command.inboxId)) {
        return { status: "noop", reason: "already_member" };
      }

      members.add(input.command.inboxId);
      return { status: "applied" };
    }

    if (!members.has(input.command.inboxId)) {
      return { status: "noop", reason: "not_member" };
    }

    members.delete(input.command.inboxId);
    return { status: "applied" };
  }
}

const loadTransportFromModule = async (
  config: WorkerConfig,
  modulePath: string,
): Promise<IngestionTransport> => {
  const loaded = (await import(toModuleSpecifier(modulePath))) as {
    createTransport?: RealTransportFactoryModule["createTransport"];
    default?: unknown;
    transport?: unknown;
  };

  let candidate: unknown;

  if (isFunction(loaded.createTransport)) {
    candidate = await loaded.createTransport(config);
  } else if (isFunction(loaded.default)) {
    candidate = await loaded.default(config);
  } else if (isRecord(loaded.default)) {
    candidate = loaded.default;
  } else {
    candidate = loaded.transport;
  }

  if (!isIngestionTransport(candidate)) {
    throw new Error("real transport module did not return a valid transport");
  }

  return candidate;
};

export const createIngestionTransport = async (
  options: CreateTransportOptions,
): Promise<IngestionTransport> => {
  const { config, logger } = options;
  const shouldAttemptBuiltInReal =
    !!config.xmtpWalletPrivateKey && !!config.xmtpDbEncryptionKey;

  if (config.transportMode === "mock") {
    logger.info("using mock transport", { mode: "mock" });
    return new DeterministicMockTransport(config);
  }

  if (config.realTransportModule && config.realTransportModule.length > 0) {
    try {
      const transport = await loadTransportFromModule(config, config.realTransportModule);
      logger.info("using real transport adapter", {
        mode: config.transportMode,
        module: config.realTransportModule,
        transportName: transport.name,
      });
      return transport;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);

      if (config.transportMode === "real") {
        throw new Error(`unable to load real transport module: ${message}`);
      }

      logger.warn("falling back to mock transport after real adapter load failure", {
        mode: config.transportMode,
        module: config.realTransportModule,
        message,
      });
      return new DeterministicMockTransport(config);
    }
  }

  if (config.transportMode === "real" || shouldAttemptBuiltInReal) {
    try {
      const transport = await createRealXmtpTransport(config, logger);
      logger.info("using built-in XMTP real transport", {
        mode: config.transportMode,
        transportName: transport.name,
      });
      return transport;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (config.transportMode === "real") {
        throw new Error(`unable to initialize built-in XMTP transport: ${message}`);
      }

      logger.warn("real transport unavailable; falling back to mock transport", {
        mode: config.transportMode,
        message,
      });
    }
  }

  logger.info("using mock transport fallback (no real transport module configured)", {
    mode: config.transportMode,
  });

  return new DeterministicMockTransport(config);
};
