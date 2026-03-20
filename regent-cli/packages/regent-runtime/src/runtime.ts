import path from "node:path";

import type { RegentConfig, RegentRpcMethod, RegentRpcResult, RuntimeStatus } from "@regent/types";

import { EnvWalletSecretSource, FileWalletSecretSource, type WalletSecretSource } from "./agent/key-store.js";
import { getCurrentAgentIdentity } from "./agent/profile.js";
import { loadConfig } from "./config.js";
import { JsonRpcError } from "./errors.js";
import {
  handleAuthSiwaLogin,
  handleAuthSiwaLogout,
  handleAuthSiwaStatus,
} from "./handlers/auth.js";
import {
  handleDoctorRun,
  handleDoctorRunFull,
  handleDoctorRunScoped,
} from "./handlers/doctor.js";
import { handleGossipsubStatus } from "./handlers/gossipsub.js";
import { handleRuntimePing, handleRuntimeShutdown, handleRuntimeStatus } from "./handlers/runtime.js";
import {
  handleTechtreeBbhLeaderboard,
  handleTechtreeBbhRun,
  handleTechtreeBbhSubmit,
  handleTechtreeBbhSync,
  handleTechtreeBbhValidate,
} from "./handlers/bbh.js";
import {
  handleTechtreeActivityList,
  handleTechtreeCommentCreate,
  handleTechtreeInboxGet,
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
import { handleXmtpStatus } from "./handlers/xmtp.js";
import { JsonRpcServer } from "./jsonrpc/server.js";
import { StateStore } from "./store/state-store.js";
import { SessionStore } from "./store/session-store.js";
import { TechtreeClient } from "./techtree/client.js";
import {
  ManagedXmtpAdapter,
  PublicTrollboxRelayAdapter,
  type GossipsubAdapter,
  type XmtpAdapter,
  TrollboxRelaySocketServer,
  WatchedNodeRelay,
  WatchedNodeRelaySocketServer,
} from "./transports/index.js";
import { resolveTrollboxRelaySocketPath } from "./transports/trollbox-relay-socket.js";

export interface RuntimeContext {
  config: RegentConfig;
  stateStore: StateStore;
  sessionStore: SessionStore;
  techtree: TechtreeClient;
  walletSecretSource: WalletSecretSource;
  xmtp: XmtpAdapter;
  gossipsub: GossipsubAdapter;
  runtime: RegentRuntime;
  requestShutdown: () => void;
}

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
  readonly xmtp: XmtpAdapter;
  readonly gossipsub: GossipsubAdapter;
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
    this.xmtp = new ManagedXmtpAdapter(this.config.xmtp);
    this.watchedNodeRelay = new WatchedNodeRelay(this.techtree);
    this.gossipsub = new PublicTrollboxRelayAdapter(
      this.config.gossipsub,
      this.techtree,
      resolveTrollboxRelaySocketPath(this.config.runtime.socketPath),
    );
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

    try {
      await this.xmtp.start();
      await this.gossipsub.start();
      await this.watchedNodeRelay.start();
      await this.trollboxRelaySocketServer.start();
      await this.watchedNodeRelaySocketServer.start();
      await this.jsonRpcServer.start();
      this.started = true;
    } catch (error) {
      await this.safeStopSubsystems();
      throw error;
    }
  }

  async stop(): Promise<void> {
    if (!this.started) {
      await this.safeStopSubsystems();
      return;
    }

    await this.safeStopSubsystems();
    this.started = false;
  }

  isStarted(): boolean {
    return this.started;
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
      xmtp: await this.xmtp.status(),
      gossipsub: await this.gossipsub.status(),
    };
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
      xmtp: this.xmtp,
      gossipsub: this.gossipsub,
      runtime: this,
      requestShutdown: () => this.requestShutdown(),
    };
  }

  private async safeStopSubsystems(): Promise<void> {
    await this.jsonRpcServer.stop().catch(() => undefined);
    await this.watchedNodeRelaySocketServer.stop().catch(() => undefined);
    await this.trollboxRelaySocketServer.stop().catch(() => undefined);
    await this.watchedNodeRelay.stop().catch(() => undefined);
    await this.gossipsub.stop().catch(() => undefined);
    await this.xmtp.stop().catch(() => undefined);
  }

  private async dispatch(method: RegentRpcMethod, params: unknown): Promise<unknown> {
    const ctx = this.context();

    switch (method) {
      case "runtime.ping":
        return handleRuntimePing();
      case "runtime.status":
        return handleRuntimeStatus(ctx);
      case "runtime.shutdown":
        return handleRuntimeShutdown(ctx);
      case "doctor.run":
        return handleDoctorRun(ctx, params as Parameters<typeof handleDoctorRun>[1]);
      case "doctor.runScoped":
        return handleDoctorRunScoped(ctx, params as Parameters<typeof handleDoctorRunScoped>[1]);
      case "doctor.runFull":
        return handleDoctorRunFull(ctx, params as Parameters<typeof handleDoctorRunFull>[1]);
      case "auth.siwa.login":
        return handleAuthSiwaLogin(ctx, (params ?? {}) as Parameters<typeof handleAuthSiwaLogin>[1]);
      case "auth.siwa.status":
        return handleAuthSiwaStatus(ctx);
      case "auth.siwa.logout":
        return handleAuthSiwaLogout(ctx);
      case "techtree.status":
        return handleTechtreeStatus(ctx);
      case "techtree.nodes.list":
        return handleTechtreeNodesList(ctx, params as Parameters<typeof handleTechtreeNodesList>[1]);
      case "techtree.nodes.get":
        return handleTechtreeNodeGet(ctx, params as Parameters<typeof handleTechtreeNodeGet>[1]);
      case "techtree.nodes.children":
        return handleTechtreeNodeChildren(ctx, params as Parameters<typeof handleTechtreeNodeChildren>[1]);
      case "techtree.nodes.comments":
        return handleTechtreeNodeComments(ctx, params as Parameters<typeof handleTechtreeNodeComments>[1]);
      case "techtree.activity.list":
        return handleTechtreeActivityList(ctx, params as Parameters<typeof handleTechtreeActivityList>[1]);
      case "techtree.search.query":
        return handleTechtreeSearchQuery(ctx, params as Parameters<typeof handleTechtreeSearchQuery>[1]);
      case "techtree.nodes.workPacket":
        return handleTechtreeNodeWorkPacket(ctx, params as Parameters<typeof handleTechtreeNodeWorkPacket>[1]);
      case "techtree.nodes.create":
        return handleTechtreeNodeCreate(ctx, params as Parameters<typeof handleTechtreeNodeCreate>[1]);
      case "techtree.comments.create":
        return handleTechtreeCommentCreate(ctx, params as Parameters<typeof handleTechtreeCommentCreate>[1]);
      case "techtree.watch.create":
        return handleTechtreeWatchCreate(ctx, params as Parameters<typeof handleTechtreeWatchCreate>[1]);
      case "techtree.watch.delete":
        return handleTechtreeWatchDelete(ctx, params as Parameters<typeof handleTechtreeWatchDelete>[1]);
      case "techtree.watch.list":
        return handleTechtreeWatchList(ctx);
      case "techtree.stars.create":
        return handleTechtreeStarCreate(ctx, params as Parameters<typeof handleTechtreeStarCreate>[1]);
      case "techtree.stars.delete":
        return handleTechtreeStarDelete(ctx, params as Parameters<typeof handleTechtreeStarDelete>[1]);
      case "techtree.inbox.get":
        return handleTechtreeInboxGet(ctx, params as Parameters<typeof handleTechtreeInboxGet>[1]);
      case "techtree.opportunities.list":
        return handleTechtreeOpportunitiesList(
          ctx,
          params as Parameters<typeof handleTechtreeOpportunitiesList>[1],
        );
      case "techtree.trollbox.history":
        return handleTechtreeTrollboxHistory(
          ctx,
          params as Parameters<typeof handleTechtreeTrollboxHistory>[1],
        );
      case "techtree.trollbox.post":
        return handleTechtreeTrollboxPost(ctx, params as Parameters<typeof handleTechtreeTrollboxPost>[1]);
      case "techtree.bbh.run":
        return handleTechtreeBbhRun(ctx, params as Parameters<typeof handleTechtreeBbhRun>[1]);
      case "techtree.bbh.submit":
        return handleTechtreeBbhSubmit(ctx, params as Parameters<typeof handleTechtreeBbhSubmit>[1]);
      case "techtree.bbh.validate":
        return handleTechtreeBbhValidate(ctx, params as Parameters<typeof handleTechtreeBbhValidate>[1]);
      case "techtree.bbh.sync":
        return handleTechtreeBbhSync(ctx, params as Parameters<typeof handleTechtreeBbhSync>[1]);
      case "techtree.bbh.leaderboard":
        return handleTechtreeBbhLeaderboard(
          ctx,
          params as Parameters<typeof handleTechtreeBbhLeaderboard>[1],
        );
      case "xmtp.status":
        return handleXmtpStatus(ctx);
      case "gossipsub.status":
        return handleGossipsubStatus(ctx);
      default:
        throw new JsonRpcError(`method not implemented: ${method}`, {
          code: "method_not_implemented",
          rpcCode: -32601,
        });
    }
  }
}
