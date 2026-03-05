import { randomUUID } from "node:crypto";
import { setTimeout as delay } from "node:timers/promises";

import type {
  CreateEventStreamOptions,
  IngestionEvent,
  IngestionMessageEvent,
  IngestionTransport,
  MembershipApplyInput,
  MembershipApplyResult,
  WorkerConfig,
} from "./types.js";

interface TransportLogger {
  info(message: string, meta?: unknown): void;
  warn(message: string, meta?: unknown): void;
}

interface XmtpConversationLike {
  id?: unknown;
  streamMessages?: (...args: unknown[]) => unknown;
  messages?: (...args: unknown[]) => unknown;
  addMembers?: (...args: unknown[]) => unknown;
  addMembersByInboxId?: (...args: unknown[]) => unknown;
  addMembersByInboxIds?: (...args: unknown[]) => unknown;
  removeMembers?: (...args: unknown[]) => unknown;
  removeMembersByInboxId?: (...args: unknown[]) => unknown;
  removeMembersByInboxIds?: (...args: unknown[]) => unknown;
}

interface XmtpClientLike {
  conversations?: {
    getConversationById?: (...args: unknown[]) => unknown;
    list?: (...args: unknown[]) => unknown;
    createGroup?: (...args: unknown[]) => unknown;
    newGroup?: (...args: unknown[]) => unknown;
    streamAllGroupMessages?: (...args: unknown[]) => unknown;
    streamAllMessages?: (...args: unknown[]) => unknown;
  };
}

const asRecord = (value: unknown): Record<string, unknown> | null => {
  return typeof value === "object" && value !== null ? (value as Record<string, unknown>) : null;
};

const asString = (value: unknown): string | null => {
  if (typeof value === "string" && value.length > 0) {
    return value;
  }
  return null;
};

const asFunction = (value: unknown): ((...args: unknown[]) => unknown) | null => {
  return typeof value === "function" ? (value as (...args: unknown[]) => unknown) : null;
};

const asAsyncIterable = (value: unknown): AsyncIterable<unknown> | null => {
  if (
    typeof value === "object" &&
    value !== null &&
    Symbol.asyncIterator in value &&
    typeof (value as Record<PropertyKey, unknown>)[Symbol.asyncIterator] === "function"
  ) {
    return value as AsyncIterable<unknown>;
  }
  return null;
};

const asArray = (value: unknown): unknown[] | null => {
  return Array.isArray(value) ? value : null;
};

const toConversationId = (value: unknown): string | null => {
  if (typeof value === "string" && value.length > 0) {
    return value;
  }

  const record = asRecord(value);
  if (!record) {
    return null;
  }

  return asString(record.id);
};

const toMethod = (target: unknown, methodName: string): ((...args: unknown[]) => unknown) | null => {
  const record = asRecord(target);
  if (!record) {
    return null;
  }

  return asFunction(record[methodName]);
};

const toUnixMs = (value: unknown): number => {
  if (value instanceof Date) {
    return value.getTime();
  }

  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string" && value.length > 0) {
    const numeric = Number(value);
    if (Number.isFinite(numeric)) {
      return numeric;
    }
    const parsedDate = Date.parse(value);
    if (!Number.isNaN(parsedDate)) {
      return parsedDate;
    }
  }

  if (typeof value === "bigint") {
    return Number(value / 1_000_000n);
  }

  return Date.now();
};

const toMessageEvent = (message: unknown, expectedConversationId: string): IngestionMessageEvent | null => {
  const record = asRecord(message);
  if (!record) {
    return null;
  }

  const conversationId =
    asString(record.conversationId) ??
    asString(record.topic) ??
    (() => {
      const conversation = asRecord(record.conversation);
      if (!conversation) return null;
      return asString(conversation.id);
    })();

  if (conversationId !== expectedConversationId) {
    return null;
  }

  const contentRecord = asRecord(record.content);
  const body =
    asString(record.content) ??
    asString(record.fallback) ??
    asString(contentRecord?.text) ??
    asString(contentRecord?.content) ??
    asString(record.body);

  if (!body || body.trim() === "") {
    return null;
  }

  const sender =
    asString(record.senderInboxId) ??
    (() => {
      const senderRecord = asRecord(record.sender);
      if (!senderRecord) return null;
      return asString(senderRecord.inboxId) ?? asString(senderRecord.address);
    })() ??
    asString(record.senderAddress) ??
    "unknown";

  const messageId =
    asString(record.id) ??
    asString(record.messageId) ??
    `${expectedConversationId}-${toUnixMs(record.sentAtNs ?? record.sentAt)}-${randomUUID()}`;

  const receivedAtMs = toUnixMs(record.sentAtNs ?? record.sentAt ?? Date.now());

  return {
    kind: "message",
    source: "xmtp",
    id: messageId,
    receivedAtMs,
    payload: {
      topic: expectedConversationId,
      sender,
      body,
    },
  };
};

const isNonPlaceholderGroupId = (groupId: string): boolean => {
  return groupId.length > 0 && !groupId.startsWith("xmtp-");
};

const callConversationMethod = async (
  conversation: XmtpConversationLike,
  methodNames: readonly string[],
  inboxId: string,
): Promise<"applied" | "noop"> => {
  for (const methodName of methodNames) {
    const method = toMethod(conversation, methodName);
    if (!method) {
      continue;
    }

    try {
      await method.call(conversation, [inboxId]);
      return "applied";
    } catch {
      await method.call(conversation, inboxId);
      return "applied";
    }
  }

  return "noop";
};

const resolveWalletClass = (moduleValue: unknown): ((privateKey: string) => { address: string }) => {
  const moduleRecord = asRecord(moduleValue);
  if (!moduleRecord) {
    throw new Error("invalid ethers module");
  }

  const directWallet = moduleRecord.Wallet;
  if (typeof directWallet === "function") {
    return (privateKey: string) => new (directWallet as new (pk: string) => { address: string })(privateKey);
  }

  const ethersNamespace = asRecord(moduleRecord.ethers);
  const nestedWallet = ethersNamespace?.Wallet;
  if (typeof nestedWallet === "function") {
    return (privateKey: string) =>
      new (nestedWallet as new (pk: string) => { address: string })(privateKey);
  }

  throw new Error("unable to resolve Wallet class from ethers module");
};

const resolveClientFactory = (
  moduleValue: unknown,
): ((signer: unknown, options: Record<string, unknown>) => Promise<XmtpClientLike>) => {
  const moduleRecord = asRecord(moduleValue);
  if (!moduleRecord) {
    throw new Error("invalid XMTP SDK module");
  }

  const directClient = asRecord(moduleRecord.Client);
  const nestedClient = asRecord(asRecord(moduleRecord.default)?.Client);
  const candidate = directClient ?? nestedClient;
  const create = candidate ? asFunction(candidate.create) : null;
  if (!create) {
    throw new Error("unable to resolve Client.create from XMTP SDK module");
  }

  return async (signer: unknown, options: Record<string, unknown>) => {
    const client = await create.call(candidate, signer, options);
    const clientRecord = asRecord(client);
    if (!clientRecord) {
      throw new Error("XMTP SDK Client.create returned invalid client");
    }
    return client as XmtpClientLike;
  };
};

const toConversation = (value: unknown): XmtpConversationLike | null => {
  const record = asRecord(value);
  if (!record) {
    return null;
  }
  return record as XmtpConversationLike;
};

class RealXmtpTransport implements IngestionTransport {
  public readonly mode = "real" as const;
  public readonly name = "xmtp-node-sdk";

  private seenMessageIds = new Set<string>();

  public constructor(
    private readonly config: WorkerConfig,
    private readonly logger: TransportLogger,
    private readonly client: XmtpClientLike,
    private readonly canonicalConversation: XmtpConversationLike,
    private readonly canonicalConversationId: string,
  ) {}

  public getCanonicalGroupId(): string {
    return this.canonicalConversationId;
  }

  public async *createEventStream(options: CreateEventStreamOptions): AsyncIterable<IngestionEvent> {
    const sdkStream = await this.resolveSdkMessageStream();
    if (sdkStream) {
      for await (const message of sdkStream) {
        if (options.signal.aborted) {
          break;
        }

        const event = toMessageEvent(message, this.canonicalConversationId);
        if (event && !this.markSeen(event.id)) {
          yield event;
        }
      }

      return;
    }

    yield* this.pollMessages(options);
  }

  public async applyMembershipCommand(input: MembershipApplyInput): Promise<MembershipApplyResult> {
    if (this.config.xmtpRequireConsent && this.config.xmtpConsentProofEndpoint) {
      const consentAllowed = await this.verifyConsent(input.command.inboxId);
      if (!consentAllowed) {
        throw new Error(`consent denied for inbox ${input.command.inboxId}`);
      }
    }

    const conversation = await this.resolveCanonicalConversation();
    if (!conversation) {
      throw new Error("unable to resolve canonical XMTP conversation");
    }

    if (input.command.op === "add_member") {
      const addResult = await callConversationMethod(
        conversation,
        ["addMembersByInboxId", "addMembersByInboxIds", "addMembers"],
        input.command.inboxId,
      );
      if (addResult === "applied") {
        return { status: "applied" };
      }
      throw new Error("XMTP SDK does not expose add-members API for this conversation");
    }

    const removeResult = await callConversationMethod(
      conversation,
      ["removeMembersByInboxId", "removeMembersByInboxIds", "removeMembers"],
      input.command.inboxId,
    );
    if (removeResult === "applied") {
      return { status: "applied" };
    }

    throw new Error("XMTP SDK does not expose remove-members API for this conversation");
  }

  private async resolveSdkMessageStream(): Promise<AsyncIterable<unknown> | null> {
    const streamAllGroupMessages = toMethod(this.client.conversations, "streamAllGroupMessages");
    if (streamAllGroupMessages) {
      const streamValue = await streamAllGroupMessages.call(this.client.conversations, {
        conversationId: this.canonicalConversationId,
      });
      const stream = asAsyncIterable(streamValue);
      if (stream) {
        return stream;
      }
    }

    const streamMessages = toMethod(this.canonicalConversation, "streamMessages");
    if (streamMessages) {
      const streamValue = await streamMessages.call(this.canonicalConversation);
      const stream = asAsyncIterable(streamValue);
      if (stream) {
        return stream;
      }
    }

    const streamAllMessages = toMethod(this.client.conversations, "streamAllMessages");
    if (!streamAllMessages) {
      return null;
    }

    const streamValue = await streamAllMessages.call(this.client.conversations);
    const stream = asAsyncIterable(streamValue);
    if (!stream) {
      return null;
    }

    return stream;
  }

  private async *pollMessages(options: CreateEventStreamOptions): AsyncIterable<IngestionEvent> {
    while (!options.signal.aborted) {
      await delay(options.pollIntervalMs, undefined, { signal: options.signal }).catch(() => undefined);
      if (options.signal.aborted) {
        break;
      }

      const conversation = await this.resolveCanonicalConversation();
      const fetchMessages = conversation ? toMethod(conversation, "messages") : null;
      if (fetchMessages) {
        const result = await fetchMessages.call(conversation, { limit: 100 });
        const messages = asArray(result) ?? [];
        for (const message of messages) {
          const event = toMessageEvent(message, this.canonicalConversationId);
          if (event && !this.markSeen(event.id)) {
            yield event;
          }
        }
      }

      yield {
        kind: "heartbeat",
        source: "xmtp",
        id: `xmtp-heartbeat-${Date.now()}`,
        receivedAtMs: Date.now(),
        payload: { lagMs: 0 },
      };
    }
  }

  private markSeen(messageId: string): boolean {
    if (this.seenMessageIds.has(messageId)) {
      return true;
    }

    this.seenMessageIds.add(messageId);
    if (this.seenMessageIds.size > 5_000) {
      const iterator = this.seenMessageIds.values();
      const first = iterator.next();
      if (!first.done) {
        this.seenMessageIds.delete(first.value);
      }
    }

    return false;
  }

  private async resolveCanonicalConversation(): Promise<XmtpConversationLike | null> {
    const getById = toMethod(this.client.conversations, "getConversationById");
    if (!getById) {
      return this.canonicalConversation;
    }

    try {
      const fetched = await getById.call(this.client.conversations, this.canonicalConversationId);
      return toConversation(fetched) ?? this.canonicalConversation;
    } catch {
      return this.canonicalConversation;
    }
  }

  private async verifyConsent(inboxId: string): Promise<boolean> {
    if (!this.config.xmtpConsentProofEndpoint) {
      return true;
    }

    try {
      const response = await fetch(this.config.xmtpConsentProofEndpoint, {
        method: "POST",
        headers: {
          "content-type": "application/json",
        },
        body: JSON.stringify({
          inbox_id: inboxId,
          room_key: this.config.canonicalRoomKey,
        }),
      });

      if (!response.ok) {
        return false;
      }

      const payload = (await response.json().catch(() => null)) as unknown;
      const payloadRecord = asRecord(payload);
      if (!payloadRecord) {
        return false;
      }

      if (payloadRecord.allowed === true) {
        return true;
      }

      const dataRecord = asRecord(payloadRecord.data);
      return dataRecord?.allowed === true;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.logger.warn("consent check failed", { message, inboxId });
      return false;
    }
  }
}

const resolveCanonicalConversation = async (
  config: WorkerConfig,
  conversations: XmtpClientLike["conversations"],
): Promise<{ conversation: XmtpConversationLike; conversationId: string }> => {
  if (!conversations) {
    throw new Error("XMTP client conversations API is unavailable");
  }

  const desiredGroupId = config.canonicalRoomGroupId;
  const getById = toMethod(conversations, "getConversationById");

  if (isNonPlaceholderGroupId(desiredGroupId) && getById) {
    const existing = await getById.call(conversations, desiredGroupId);
    const existingConversation = toConversation(existing);
    if (existingConversation) {
      return { conversation: existingConversation, conversationId: desiredGroupId };
    }
  }

  const listConversations = toMethod(conversations, "list");
  if (listConversations) {
    const listResult = await listConversations.call(conversations);
    const list = asArray(listResult) ?? [];
    for (const item of list) {
      const conversation = toConversation(item);
      const conversationId = toConversationId(conversation?.id);
      if (!conversation || !conversationId) {
        continue;
      }
      if (conversationId === desiredGroupId) {
        return { conversation, conversationId };
      }
    }
  }

  if (!config.xmtpCreateGroupIfMissing) {
    throw new Error(
      `canonical group not found and XMTP_CREATE_GROUP_IF_MISSING=false (group_id=${desiredGroupId})`,
    );
  }

  const createGroup = toMethod(conversations, "createGroup") ?? toMethod(conversations, "newGroup");
  if (!createGroup) {
    throw new Error("XMTP SDK does not expose conversations.createGroup/newGroup");
  }

  const candidates: readonly unknown[] = [
    [[], { name: config.canonicalRoomName }],
    [[], { groupName: config.canonicalRoomName }],
    [[]],
  ];

  for (const candidate of candidates) {
    try {
      const args = asArray(candidate) ?? [];
      const created = await createGroup.call(conversations, ...args);
      const conversation = toConversation(created);
      const conversationId = toConversationId(conversation?.id);
      if (conversation && conversationId) {
        return { conversation, conversationId };
      }
    } catch {
      continue;
    }
  }

  throw new Error("unable to create canonical XMTP group");
};

export const createRealXmtpTransport = async (
  config: WorkerConfig,
  logger: TransportLogger,
): Promise<IngestionTransport> => {
  if (!config.xmtpWalletPrivateKey) {
    throw new Error("XMTP_WALLET_PRIVATE_KEY is required for real XMTP transport");
  }
  if (!config.xmtpDbEncryptionKey) {
    throw new Error("XMTP_DB_ENCRYPTION_KEY is required for real XMTP transport");
  }

  const xmtpModule = await import(config.xmtpSdkModule);
  const ethersModule = await import(config.xmtpEthersModule);
  const walletFactory = resolveWalletClass(ethersModule);
  const clientFactory = resolveClientFactory(xmtpModule);

  const signer = walletFactory(config.xmtpWalletPrivateKey);
  const client = await clientFactory(signer, {
    env: config.xmtpEnv,
    dbEncryptionKey: config.xmtpDbEncryptionKey,
  });

  const canonical = await resolveCanonicalConversation(config, client.conversations);
  logger.info("XMTP real transport connected", {
    env: config.xmtpEnv,
    groupId: canonical.conversationId,
  });

  return new RealXmtpTransport(
    config,
    logger,
    client,
    canonical.conversation,
    canonical.conversationId,
  );
};
