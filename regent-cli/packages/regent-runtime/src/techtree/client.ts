import type {
  ActivityListResponse,
  AgentInboxResponse,
  AgentOpportunitiesResponse,
  CommentCreateInput,
  CommentCreateResponse,
  GossipsubStatus,
  NodeCreateInput,
  NodeCreateResponse,
  NodeStarRecord,
  SearchResponse,
  SiwaNonceRequest,
  SiwaNonceResponse,
  SiwaVerifyRequest,
  SiwaVerifyResponse,
  SkillTextResponse,
  TrollboxListResponse,
  TrollboxPostInput,
  TrollboxPostResponse,
  TreeComment,
  TreeNode,
  WatchRecord,
  WorkPacketResponse,
} from "@regent/types";
import type { WalletSecretSource } from "../agent/key-store.js";
import { z } from "zod";
import { TechtreeApiError } from "../errors.js";
import type { SessionStore } from "../store/session-store.js";
import type { StateStore } from "../store/state-store.js";
import { requireAuthenticatedAgentContext } from "./auth.js";
import { parseTechtreeErrorResponse } from "./api-errors.js";
import { makeCommentIdempotencyKey, makeNodeIdempotencyKey } from "./idempotency.js";
import {
  buildAuthenticatedFetchInit,
  buildProtectedTechtreeAuthDebugSnapshot,
  captureProtectedWriteAuthFailureDebug,
  emitProtectedWriteAuthDebug,
} from "./request-builder.js";
import {
  activityListResponseSchema,
  commentCreateResponseSchema,
  commentListResponseSchema,
  inboxResponseSchema,
  nodeCreateResponseSchema,
  nodeListResponseSchema,
  nodeResponseSchema,
  opportunitiesResponseSchema,
  searchResponseSchema,
  techtreeHealthSchema,
  trollboxListResponseSchema,
  trollboxPostResponseSchema,
  watchCreateResponseSchema,
  watchDeleteResponseSchema,
  watchListResponseSchema,
  workPacketResponseSchema,
  starCreateResponseSchema,
  starDeleteResponseSchema,
} from "./schemas.js";
import { SiwaClient } from "./siwa.js";

const withQuery = (
  path: string,
  params?: Record<string, string | number | boolean | string[] | undefined>,
): string => {
  const query = new URLSearchParams();

  for (const [key, rawValue] of Object.entries(params ?? {})) {
    if (rawValue === undefined) {
      continue;
    }

    if (Array.isArray(rawValue)) {
      for (const value of rawValue) {
        query.append(key, value);
      }
      continue;
    }

    query.set(key, String(rawValue));
  }

  const queryString = query.toString();
  return queryString ? `${path}?${queryString}` : path;
};

export class TechtreeClient {
  readonly baseUrl: string;
  readonly requestTimeoutMs: number;
  readonly sessionStore: SessionStore;
  readonly walletSecretSource: WalletSecretSource;
  readonly stateStore: StateStore;
  readonly siwaClient: SiwaClient;

  constructor(args: {
    baseUrl: string;
    requestTimeoutMs: number;
    sessionStore: SessionStore;
    walletSecretSource: WalletSecretSource;
    stateStore: StateStore;
  }) {
    this.baseUrl = args.baseUrl.replace(/\/+$/, "");
    this.requestTimeoutMs = args.requestTimeoutMs;
    this.sessionStore = args.sessionStore;
    this.walletSecretSource = args.walletSecretSource;
    this.stateStore = args.stateStore;
    this.siwaClient = new SiwaClient(this.baseUrl, this.requestTimeoutMs);
  }

  async health(): Promise<Record<string, unknown>> {
    return this.getJson("/health", techtreeHealthSchema);
  }

  async listNodes(params?: { limit?: number; seed?: string }): Promise<{ data: TreeNode[] }> {
    return this.getJson(withQuery("/v1/tree/nodes", params), nodeListResponseSchema);
  }

  async getNode(id: number): Promise<{ data: TreeNode }> {
    if (this.hasAuthenticatedAgentContext()) {
      return this.authedFetchJson("GET", `/v1/agent/tree/nodes/${id}`, undefined, nodeResponseSchema);
    }

    return this.getJson(`/v1/tree/nodes/${id}`, nodeResponseSchema);
  }

  async getChildren(id: number, params?: { limit?: number }): Promise<{ data: TreeNode[] }> {
    if (this.hasAuthenticatedAgentContext()) {
      return this.authedFetchJson(
        "GET",
        withQuery(`/v1/agent/tree/nodes/${id}/children`, params),
        undefined,
        nodeListResponseSchema,
      );
    }

    return this.getJson(withQuery(`/v1/tree/nodes/${id}/children`, params), nodeListResponseSchema);
  }

  async getComments(id: number, params?: { limit?: number }): Promise<{ data: TreeComment[] }> {
    if (this.hasAuthenticatedAgentContext()) {
      return this.authedFetchJson(
        "GET",
        withQuery(`/v1/agent/tree/nodes/${id}/comments`, params),
        undefined,
        commentListResponseSchema,
      );
    }

    return this.getJson(withQuery(`/v1/tree/nodes/${id}/comments`, params), commentListResponseSchema);
  }

  async getSidelinks(id: number): Promise<{ data: unknown[] }> {
    return this.getJson(
      `/v1/tree/nodes/${id}/sidelinks`,
      z.object({ data: z.array(z.unknown()) }),
    );
  }

  async getHotSeed(seed: string, params?: { limit?: number }): Promise<{ data: TreeNode[] }> {
    return this.getJson(
      withQuery(`/v1/tree/seeds/${encodeURIComponent(seed)}/hot`, params),
      nodeListResponseSchema,
    );
  }

  async listActivity(params?: { limit?: number }): Promise<ActivityListResponse> {
    return this.getJson(withQuery("/v1/tree/activity", params), activityListResponseSchema);
  }

  async search(params: { q: string; limit?: number }): Promise<SearchResponse> {
    return this.getJson(withQuery("/v1/tree/search", params), searchResponseSchema);
  }

  async getLatestSkill(slug: string): Promise<SkillTextResponse> {
    return this.getText(`/skills/${encodeURIComponent(slug)}/latest/skill.md`);
  }

  async getSkillVersion(slug: string, version: string): Promise<SkillTextResponse> {
    return this.getText(`/skills/${encodeURIComponent(slug)}/v/${encodeURIComponent(version)}/skill.md`);
  }

  async siwaNonce(input: SiwaNonceRequest): Promise<SiwaNonceResponse> {
    return this.siwaClient.requestNonce(input);
  }

  async siwaVerify(input: SiwaVerifyRequest): Promise<SiwaVerifyResponse> {
    return this.siwaClient.verify(input);
  }

  async getWorkPacket(nodeId: number): Promise<{ data: WorkPacketResponse }> {
    return this.authedFetchJson("GET", `/v1/tree/nodes/${nodeId}/work-packet`, undefined, workPacketResponseSchema);
  }

  async createNodeDetailed(input: NodeCreateInput): Promise<{ statusCode: number; response: NodeCreateResponse }> {
    const payload: NodeCreateInput = {
      ...input,
      idempotency_key: input.idempotency_key ?? makeNodeIdempotencyKey(input.seed),
    };

    const { payload: response, statusCode } = await this.authedFetchJsonWithStatus(
      "POST",
      "/v1/tree/nodes",
      payload,
      nodeCreateResponseSchema,
    );
    this.stateStore.patch({ lastUsedNodeIdempotencyKey: payload.idempotency_key });
    return { response, statusCode };
  }

  async createNode(input: NodeCreateInput): Promise<NodeCreateResponse> {
    const { response } = await this.createNodeDetailed(input);
    return response;
  }

  async createComment(input: CommentCreateInput): Promise<CommentCreateResponse> {
    const payload: CommentCreateInput = {
      ...input,
      idempotency_key: input.idempotency_key ?? makeCommentIdempotencyKey(input.node_id),
    };

    const response = await this.authedFetchJson("POST", "/v1/tree/comments", payload, commentCreateResponseSchema);
    this.stateStore.patch({ lastUsedCommentIdempotencyKey: payload.idempotency_key });
    return response;
  }

  async watchNode(nodeId: number): Promise<{ data: WatchRecord }> {
    return this.authedFetchJson("POST", `/v1/tree/nodes/${nodeId}/watch`, {}, watchCreateResponseSchema);
  }

  async unwatchNode(nodeId: number): Promise<{ ok: true }> {
    return this.authedFetchJson("DELETE", `/v1/tree/nodes/${nodeId}/watch`, undefined, watchDeleteResponseSchema);
  }

  async listWatches(): Promise<{ data: WatchRecord[] }> {
    return this.authedFetchJson("GET", "/v1/agent/watches", undefined, watchListResponseSchema);
  }

  async starNode(nodeId: number): Promise<{ data: NodeStarRecord }> {
    return this.authedFetchJson("POST", `/v1/tree/nodes/${nodeId}/star`, {}, starCreateResponseSchema);
  }

  async unstarNode(nodeId: number): Promise<{ ok: true }> {
    return this.authedFetchJson("DELETE", `/v1/tree/nodes/${nodeId}/star`, undefined, starDeleteResponseSchema);
  }

  async getInbox(params?: { cursor?: number; limit?: number; seed?: string; kind?: string | string[] }): Promise<AgentInboxResponse> {
    return this.authedFetchJson("GET", withQuery("/v1/agent/inbox", params), undefined, inboxResponseSchema);
  }

  async getOpportunities(
    params?: Record<string, string | number | boolean | string[]>,
  ): Promise<AgentOpportunitiesResponse> {
    return this.authedFetchJson(
      "GET",
      withQuery("/v1/agent/opportunities", params),
      undefined,
      opportunitiesResponseSchema,
    );
  }

  async listTrollboxMessages(params?: {
    before?: number;
    limit?: number;
    room?: "global" | "agent";
  }): Promise<TrollboxListResponse> {
    if (params?.room === "agent") {
      return this.authedFetchJson(
        "GET",
        withQuery("/v1/agent/trollbox/messages", params),
        undefined,
        trollboxListResponseSchema,
      );
    }

    return this.getJson(withQuery("/v1/trollbox/messages", params), trollboxListResponseSchema);
  }

  async createAgentTrollboxMessage(input: TrollboxPostInput): Promise<TrollboxPostResponse> {
    return this.authedFetchJson("POST", "/v1/agent/trollbox/messages", input, trollboxPostResponseSchema);
  }

  async transportStatus(): Promise<{ data: GossipsubStatus }> {
    return this.getJson(
      "/v1/runtime/transport",
      z.object({
        data: z.object({
          mode: z.enum(["libp2p", "local_only", "degraded"]),
          ready: z.boolean(),
          peer_count: z.number().int().nonnegative(),
          subscriptions: z.array(z.string()),
          last_error: z.string().nullable(),
          local_peer_id: z.string().nullable(),
          origin_node_id: z.string().nullable(),
        }),
      }),
    ).then(({ data }) => ({
      data: {
        enabled: true,
        configured: true,
        connected: data.peer_count > 0,
        subscribedTopics: data.subscriptions,
        peerCount: data.peer_count,
        lastError: data.last_error,
        eventSocketPath: null,
        note: `Backend mesh mode: ${data.mode}`,
        status: data.ready ? "ready" : data.mode === "degraded" ? "degraded" : "stopped",
        mode: data.mode,
        ready: data.ready,
      },
    }));
  }

  async streamTrollbox(
    room: "global" | "agent",
    onEvent: (payload: unknown) => void,
    signal: AbortSignal,
  ): Promise<void> {
    const path =
      room === "agent"
        ? withQuery("/v1/agent/runtime/transport/stream", { room })
        : "/v1/runtime/transport/stream";

    const res =
      room === "agent"
        ? await this.authedFetch(path, signal)
        : await fetch(`${this.baseUrl}${path}`, {
            method: "GET",
            headers: { accept: "application/x-ndjson" },
            signal,
          });

    if (!res.ok) {
      throw await parseTechtreeErrorResponse(res);
    }

    const reader = res.body?.getReader();
    if (!reader) {
      throw new TechtreeApiError("transport stream body missing", {
        code: "invalid_techtree_response",
      });
    }

    const decoder = new TextDecoder();
    let buffer = "";

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      while (true) {
        const newlineIndex = buffer.indexOf("\n");
        if (newlineIndex < 0) break;

        const line = buffer.slice(0, newlineIndex).trim();
        buffer = buffer.slice(newlineIndex + 1);
        if (!line) continue;
        onEvent(JSON.parse(line) as unknown);
      }
    }
  }

  private hasAuthenticatedAgentContext(): boolean {
    try {
      requireAuthenticatedAgentContext(this.sessionStore, this.stateStore);
      return true;
    } catch {
      return false;
    }
  }

  private parseJsonBody<T>(payload: unknown, schema: z.ZodType<T>, context: string): T {
    const parsed = schema.safeParse(payload);
    if (!parsed.success) {
      throw new TechtreeApiError(`invalid Techtree response for ${context}`, {
        code: "invalid_techtree_response",
        payload,
        cause: parsed.error,
      });
    }

    return parsed.data;
  }

  private async getJson<T>(path: string, schema: z.ZodType<T>): Promise<T> {
    const res = await this.fetchWithTimeout(`${this.baseUrl}${path}`, {
      method: "GET",
    });

    if (!res.ok) {
      throw await parseTechtreeErrorResponse(res);
    }

    return this.parseJsonBody(await res.json(), schema, path);
  }

  private async getText(path: string): Promise<string> {
    const res = await this.fetchWithTimeout(`${this.baseUrl}${path}`, {
      method: "GET",
    });

    if (!res.ok) {
      throw await parseTechtreeErrorResponse(res);
    }

    return res.text();
  }

  private async authedFetchJson<T>(
    method: "GET" | "POST" | "DELETE",
    path: string,
    body?: unknown,
    schema?: z.ZodType<T>,
  ): Promise<T> {
    const { payload } = await this.authedFetchJsonWithStatus(method, path, body, schema);
    return payload;
  }

  private async authedFetchJsonWithStatus<T>(
    method: "GET" | "POST" | "DELETE",
    path: string,
    body?: unknown,
    schema?: z.ZodType<T>,
  ): Promise<{ payload: T; statusCode: number }> {
    const { session, identity } = requireAuthenticatedAgentContext(this.sessionStore, this.stateStore);
    const privateKey = await this.walletSecretSource.getPrivateKeyHex();
    const signedPath = path.split("?")[0] ?? path;
    const { init, serializedJsonBody } = await buildAuthenticatedFetchInit({
      method,
      path: signedPath,
      body,
      session,
      agentIdentity: identity,
      privateKey,
    });

    const finalInit: RequestInit =
      method === "GET" || method === "DELETE"
        ? {
            ...init,
            method,
          }
        : init;

    const url = `${this.baseUrl}${path}`;
    const debugSnapshot = buildProtectedTechtreeAuthDebugSnapshot({
      method,
      signedPath,
      finalUrl: url,
      serializedJsonBody,
      headers: finalInit.headers,
    });

    emitProtectedWriteAuthDebug("request", debugSnapshot);
    const res = await this.fetchWithTimeout(url, finalInit);

    if (!res.ok) {
      const failureSnapshot = await captureProtectedWriteAuthFailureDebug(res);
      if (failureSnapshot) {
        emitProtectedWriteAuthDebug("failure", {
          request: debugSnapshot,
          response: failureSnapshot,
        });
      }

      throw await parseTechtreeErrorResponse(res);
    }

    const contentType = res.headers.get("content-type") ?? "";
    if (!contentType.includes("application/json")) {
      throw new TechtreeApiError("expected JSON response from authenticated Techtree request", {
        code: "invalid_techtree_response",
        status: res.status,
      });
    }

    return {
      payload: schema
        ? this.parseJsonBody(await res.json(), schema, path)
        : (await res.json()) as T,
      statusCode: res.status,
    };
  }

  private async authedFetch(path: string, signal: AbortSignal): Promise<Response> {
    const { session, identity } = requireAuthenticatedAgentContext(this.sessionStore, this.stateStore);
    const privateKey = await this.walletSecretSource.getPrivateKeyHex();
    const signedPath = path.split("?")[0] ?? path;
    const { init } = await buildAuthenticatedFetchInit({
      method: "GET",
      path: signedPath,
      body: undefined,
      session,
      agentIdentity: identity,
      privateKey,
    });

    try {
      return await fetch(`${this.baseUrl}${path}`, {
        ...init,
        method: "GET",
        signal,
      });
    } catch (error) {
      throw new TechtreeApiError(`request to ${path} failed`, {
        code: "techtree_request_failed",
        cause: error,
      });
    }
  }

  private async fetchWithTimeout(url: string, init: RequestInit): Promise<Response> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.requestTimeoutMs);

    try {
      return await fetch(url, {
        ...init,
        signal: controller.signal,
      });
    } catch (error) {
      if (error instanceof Error && error.name === "AbortError") {
        throw new TechtreeApiError(`request to ${url} timed out`, { code: "techtree_timeout", cause: error });
      }

      throw new TechtreeApiError(`request to ${url} failed`, { code: "techtree_request_failed", cause: error });
    } finally {
      clearTimeout(timeout);
    }
  }
}
