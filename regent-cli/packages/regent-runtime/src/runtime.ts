import path from "node:path";

import type { RegentConfig, RegentRpcMethod, RuntimeStatus } from "@regent/types";

import { EnvWalletSecretSource, FileWalletSecretSource, type WalletSecretSource } from "./agent/key-store.js";
import { getCurrentAgentIdentity } from "./agent/profile.js";
import { loadConfig } from "./config.js";
import { JsonRpcError } from "./errors.js";
import {
  handleDoctorRun,
  handleDoctorRunFull,
  handleDoctorRunScoped,
} from "./handlers/doctor.js";
import {
  handleAuthSiwaLogin,
  handleAuthSiwaLogout,
  handleAuthSiwaStatus,
} from "./handlers/auth.js";
import { handleGossipsubStatus } from "./handlers/gossipsub.js";
import { handleRuntimePing, handleRuntimeShutdown, handleRuntimeStatus } from "./handlers/runtime.js";
import { handleXmtpStatus } from "./handlers/xmtp.js";
import {
  handleTechtreeCommentCreate,
  handleTechtreeInboxGet,
  handleTechtreeActivityList,
  handleTechtreeNodeChildren,
  handleTechtreeNodeComments,
  handleTechtreeNodeCreate,
  handleTechtreeNodeGet,
  handleTechtreeNodeWorkPacket,
  handleTechtreeNodesList,
  handleTechtreeOpportunitiesList,
  handleTechtreeSearchQuery,
  handleTechtreeStarCreate,
  handleTechtreeStarDelete,
  handleTechtreeStatus,
  handleTechtreeTrollboxHistory,
  handleTechtreeTrollboxPost,
  handleTechtreeWatchCreate,
  handleTechtreeWatchDelete,
  handleTechtreeWatchList,
} from "./handlers/techtree.js";
import { REGENT_RPC_METHODS } from "./jsonrpc/methods.js";
import { JsonRpcServer } from "./jsonrpc/server.js";
import { StateStore } from "./store/state-store.js";
import { SessionStore } from "./store/session-store.js";
import { TechtreeClient } from "./techtree/client.js";
import {
  PublicTrollboxRelayAdapter,
  TrollboxRelaySocketServer,
  WatchedNodeRelay,
  WatchedNodeRelaySocketServer,
  XmtpAdapter,
  resolveTrollboxRelaySocketPath,
  type GossipsubAdapter,
} from "./transports/index.js";

export interface RuntimeContext {
  config: RegentConfig;
  stateStore: StateStore;
  sessionStore: SessionStore;
  techtree: TechtreeClient;
  walletSecretSource: WalletSecretSource;
  gossipsub: GossipsubAdapter;
  xmtp: XmtpAdapter;
  runtime: RegentRuntime;
  requestShutdown: () => void;
}

type RpcHandlerMap = Record<RegentRpcMethod, (ctx: RuntimeContext, params: unknown) => Promise<unknown> | unknown>;

const createWalletSecretSource = (config: RegentConfig): WalletSecretSource => {
  const envVarName = config.wallet.privateKeyEnv;
  if (process.env[envVarName]) {
    return new EnvWalletSecretSource(envVarName);
  }

  return new FileWalletSecretSource(config.wallet.keystorePath);
};

export class RegentRuntime {
  readonly configPath?: string;
  readonly config: RegentConfig;
  readonly stateStore: StateStore;
  readonly sessionStore: SessionStore;
  readonly walletSecretSource: WalletSecretSource;
  readonly techtree: TechtreeClient;
  readonly gossipsub: GossipsubAdapter;
  readonly xmtp: XmtpAdapter;
  readonly trollboxRelaySocketServer: TrollboxRelaySocketServer;
  readonly watchedNodeRelay: WatchedNodeRelay;
  readonly watchedNodeRelaySocketServer: WatchedNodeRelaySocketServer;
  readonly jsonRpcServer: JsonRpcServer;

  private started = false;
  private shutdownRequested = false;

  constructor(configPath?: string) {
    this.configPath = configPath;
    this.config = loadConfig(configPath);
    this.stateStore = new StateStore(path.join(this.config.runtime.stateDir, "runtime-state.json"));
    this.sessionStore = new SessionStore(this.stateStore);
    this.walletSecretSource = createWalletSecretSource(this.config);
    this.techtree = new TechtreeClient({
      baseUrl: this.config.techtree.baseUrl,
      requestTimeoutMs: this.config.techtree.requestTimeoutMs,
      sessionStore: this.sessionStore,
      walletSecretSource: this.walletSecretSource,
      stateStore: this.stateStore,
    });
    // The runtime owns a local trollbox transport socket while Techtree remains the canonical source of transport mode.
    this.gossipsub = new PublicTrollboxRelayAdapter(
      this.config.gossipsub,
      this.techtree,
      resolveTrollboxRelaySocketPath(this.config.runtime.socketPath),
    );
    this.xmtp = new XmtpAdapter(this.config.xmtp);
    this.watchedNodeRelay = new WatchedNodeRelay(this.techtree);
    this.trollboxRelaySocketServer = new TrollboxRelaySocketServer(
      this.config.runtime.socketPath,
      this.gossipsub,
    );
    this.watchedNodeRelaySocketServer = new WatchedNodeRelaySocketServer(
      this.config.runtime.socketPath,
      this.watchedNodeRelay,
    );
    this.jsonRpcServer = new JsonRpcServer(this.config.runtime.socketPath, async (method, params) =>
      this.dispatch(method, params),
    );
  }

  async start(): Promise<void> {
    if (this.started) {
      return;
    }

    const cleanupStack: Array<() => Promise<void>> = [];

    try {
      await this.gossipsub.start();
      cleanupStack.unshift(() => this.gossipsub.stop());

      await this.xmtp.start();
      cleanupStack.unshift(() => this.xmtp.stop());

      await this.watchedNodeRelay.start();
      cleanupStack.unshift(() => this.watchedNodeRelay.stop());

      if (this.config.gossipsub.enabled) {
        await this.trollboxRelaySocketServer.start();
        cleanupStack.unshift(() => this.trollboxRelaySocketServer.stop());
      }

      await this.watchedNodeRelaySocketServer.start();
      cleanupStack.unshift(() => this.watchedNodeRelaySocketServer.stop());

      await this.jsonRpcServer.start();
      cleanupStack.unshift(() => this.jsonRpcServer.stop());

      this.started = true;
    } catch (error) {
      for (const cleanup of cleanupStack) {
        try {
          await cleanup();
        } catch {
          // Preserve the startup error; cleanup should be best-effort.
        }
      }

      throw error;
    }
  }

  async stop(): Promise<void> {
    if (!this.started) {
      return;
    }

    await this.jsonRpcServer.stop();
    await this.trollboxRelaySocketServer.stop();
    await this.watchedNodeRelaySocketServer.stop();
    await this.watchedNodeRelay.stop();
    await this.xmtp.stop();
    await this.gossipsub.stop();
    this.started = false;
  }

  async status(): Promise<RuntimeStatus> {
    let health: RuntimeStatus["techtree"] = null;

    try {
      const startedAt = Date.now();
      const payload = await this.techtree.health();
      health = {
        ok: true,
        baseUrl: this.config.techtree.baseUrl,
        latencyMs: Date.now() - startedAt,
        payload,
      };
    } catch (error) {
      health = {
        ok: false,
        baseUrl: this.config.techtree.baseUrl,
        latencyMs: null,
        error: error instanceof Error ? error.message : "health check failed",
      };
    }

    const session = this.sessionStore.getSiwaSession();

    return {
      running: this.started,
      socketPath: this.config.runtime.socketPath,
      stateDir: this.config.runtime.stateDir,
      logLevel: this.config.runtime.logLevel,
      authenticated: !!session && !this.sessionStore.isReceiptExpired(),
      session: session
        ? {
            walletAddress: session.walletAddress,
            chainId: session.chainId,
            receiptExpiresAt: session.receiptExpiresAt,
          }
        : null,
      agentIdentity: getCurrentAgentIdentity(this.stateStore),
      techtree: health,
      gossipsub: await this.gossipsub.status(),
      xmtp: await this.xmtp.status(),
    };
  }

  isStarted(): boolean {
    return this.started;
  }

  async doctorRun(
    params?: Parameters<typeof handleDoctorRun>[1],
  ): Promise<Awaited<ReturnType<typeof handleDoctorRun>>> {
    return handleDoctorRun(this.context(), params);
  }

  async doctorRunScoped(
    params: Parameters<typeof handleDoctorRunScoped>[1],
  ): Promise<Awaited<ReturnType<typeof handleDoctorRunScoped>>> {
    return handleDoctorRunScoped(this.context(), params);
  }

  async doctorRunFull(
    params?: Parameters<typeof handleDoctorRunFull>[1],
  ): Promise<Awaited<ReturnType<typeof handleDoctorRunFull>>> {
    return handleDoctorRunFull(this.context(), params);
  }

  requestShutdown(): void {
    if (this.shutdownRequested) {
      return;
    }

    this.shutdownRequested = true;
    setTimeout(() => {
      void this.stop();
    }, 0);
  }

  private context(): RuntimeContext {
    return {
      config: this.config,
      stateStore: this.stateStore,
      sessionStore: this.sessionStore,
      techtree: this.techtree,
      walletSecretSource: this.walletSecretSource,
      gossipsub: this.gossipsub,
      xmtp: this.xmtp,
      runtime: this,
      requestShutdown: () => this.requestShutdown(),
    };
  }

  private async dispatch(method: RegentRpcMethod, params: unknown): Promise<unknown> {
    const ctx = this.context();
    const handler = RPC_HANDLER_MAP[method];
    if (!handler) {
      throw new JsonRpcError(`method not implemented: ${method}`, {
        code: "method_not_implemented",
        rpcCode: -32601,
      });
    }

    return handler(ctx, params);
  }
}

const RPC_HANDLER_MAP = {
  [REGENT_RPC_METHODS.runtimePing]: (_ctx: RuntimeContext) => handleRuntimePing(),
  [REGENT_RPC_METHODS.runtimeStatus]: (ctx: RuntimeContext) => handleRuntimeStatus(ctx),
  [REGENT_RPC_METHODS.runtimeShutdown]: (ctx: RuntimeContext) => handleRuntimeShutdown(ctx),
  [REGENT_RPC_METHODS.doctorRun]: (ctx: RuntimeContext, params: unknown) =>
    handleDoctorRun(ctx, params as Parameters<typeof handleDoctorRun>[1]),
  [REGENT_RPC_METHODS.doctorRunScoped]: (ctx: RuntimeContext, params: unknown) =>
    handleDoctorRunScoped(ctx, params as Parameters<typeof handleDoctorRunScoped>[1]),
  [REGENT_RPC_METHODS.doctorRunFull]: (ctx: RuntimeContext, params: unknown) =>
    handleDoctorRunFull(ctx, params as Parameters<typeof handleDoctorRunFull>[1]),
  [REGENT_RPC_METHODS.authSiwaLogin]: (ctx: RuntimeContext, params: unknown) =>
    handleAuthSiwaLogin(ctx, (params ?? {}) as Parameters<typeof handleAuthSiwaLogin>[1]),
  [REGENT_RPC_METHODS.authSiwaStatus]: (ctx: RuntimeContext) => handleAuthSiwaStatus(ctx),
  [REGENT_RPC_METHODS.authSiwaLogout]: (ctx: RuntimeContext) => handleAuthSiwaLogout(ctx),
  [REGENT_RPC_METHODS.techtreeStatus]: (ctx: RuntimeContext) => handleTechtreeStatus(ctx),
  [REGENT_RPC_METHODS.techtreeNodesList]: (ctx: RuntimeContext, params: unknown) =>
    handleTechtreeNodesList(ctx, params as Parameters<typeof handleTechtreeNodesList>[1]),
  [REGENT_RPC_METHODS.techtreeNodesGet]: (ctx: RuntimeContext, params: unknown) =>
    handleTechtreeNodeGet(ctx, params as Parameters<typeof handleTechtreeNodeGet>[1]),
  [REGENT_RPC_METHODS.techtreeNodesChildren]: (ctx: RuntimeContext, params: unknown) =>
    handleTechtreeNodeChildren(ctx, params as Parameters<typeof handleTechtreeNodeChildren>[1]),
  [REGENT_RPC_METHODS.techtreeNodesComments]: (ctx: RuntimeContext, params: unknown) =>
    handleTechtreeNodeComments(ctx, params as Parameters<typeof handleTechtreeNodeComments>[1]),
  [REGENT_RPC_METHODS.techtreeActivityList]: (ctx: RuntimeContext, params: unknown) =>
    handleTechtreeActivityList(ctx, params as Parameters<typeof handleTechtreeActivityList>[1]),
  [REGENT_RPC_METHODS.techtreeSearchQuery]: (ctx: RuntimeContext, params: unknown) =>
    handleTechtreeSearchQuery(ctx, params as Parameters<typeof handleTechtreeSearchQuery>[1]),
  [REGENT_RPC_METHODS.techtreeNodesWorkPacket]: (ctx: RuntimeContext, params: unknown) =>
    handleTechtreeNodeWorkPacket(ctx, params as Parameters<typeof handleTechtreeNodeWorkPacket>[1]),
  [REGENT_RPC_METHODS.techtreeNodesCreate]: (ctx: RuntimeContext, params: unknown) =>
    handleTechtreeNodeCreate(ctx, params as Parameters<typeof handleTechtreeNodeCreate>[1]),
  [REGENT_RPC_METHODS.techtreeCommentsCreate]: (ctx: RuntimeContext, params: unknown) =>
    handleTechtreeCommentCreate(ctx, params as Parameters<typeof handleTechtreeCommentCreate>[1]),
  [REGENT_RPC_METHODS.techtreeWatchCreate]: (ctx: RuntimeContext, params: unknown) =>
    handleTechtreeWatchCreate(ctx, params as Parameters<typeof handleTechtreeWatchCreate>[1]),
  [REGENT_RPC_METHODS.techtreeWatchDelete]: (ctx: RuntimeContext, params: unknown) =>
    handleTechtreeWatchDelete(ctx, params as Parameters<typeof handleTechtreeWatchDelete>[1]),
  [REGENT_RPC_METHODS.techtreeWatchList]: (ctx: RuntimeContext) =>
    handleTechtreeWatchList(ctx),
  [REGENT_RPC_METHODS.techtreeStarsCreate]: (ctx: RuntimeContext, params: unknown) =>
    handleTechtreeStarCreate(ctx, params as Parameters<typeof handleTechtreeStarCreate>[1]),
  [REGENT_RPC_METHODS.techtreeStarsDelete]: (ctx: RuntimeContext, params: unknown) =>
    handleTechtreeStarDelete(ctx, params as Parameters<typeof handleTechtreeStarDelete>[1]),
  [REGENT_RPC_METHODS.techtreeInboxGet]: (ctx: RuntimeContext, params: unknown) =>
    handleTechtreeInboxGet(ctx, params as Parameters<typeof handleTechtreeInboxGet>[1]),
  [REGENT_RPC_METHODS.techtreeOpportunitiesList]: (ctx: RuntimeContext, params: unknown) =>
    handleTechtreeOpportunitiesList(ctx, params as Parameters<typeof handleTechtreeOpportunitiesList>[1]),
  [REGENT_RPC_METHODS.techtreeTrollboxHistory]: (ctx: RuntimeContext, params: unknown) =>
    handleTechtreeTrollboxHistory(ctx, params as Parameters<typeof handleTechtreeTrollboxHistory>[1]),
  [REGENT_RPC_METHODS.techtreeTrollboxPost]: (ctx: RuntimeContext, params: unknown) =>
    handleTechtreeTrollboxPost(ctx, params as Parameters<typeof handleTechtreeTrollboxPost>[1]),
  [REGENT_RPC_METHODS.gossipsubStatus]: (ctx: RuntimeContext) => handleGossipsubStatus(ctx),
  [REGENT_RPC_METHODS.xmtpStatus]: (ctx: RuntimeContext) => handleXmtpStatus(ctx),
} satisfies RpcHandlerMap;
