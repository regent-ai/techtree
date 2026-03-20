import type { AuthStatusResponse, SiwaVerifyResponse } from "./auth.js";
import type { RegentConfig } from "./config.js";
import type { DoctorReport, DoctorRunFullParams, DoctorRunParams, DoctorRunScopedParams } from "./doctor.js";
import type { GossipsubStatus } from "./gossipsub.js";
import type { RuntimeStatus } from "./runtime.js";
import type { XmtpStatus } from "./xmtp-status.js";
import type {
  ActivityListResponse,
  AgentInboxResponse,
  AgentOpportunitiesResponse,
  CommentCreateInput,
  CommentCreateResponse,
  NodeCreateInput,
  NodeCreateResponse,
  NodeStarRecord,
  SearchResponse,
  TreeComment,
  TreeNode,
  WatchRecord,
  WorkPacketResponse,
  TrollboxListResponse,
  TrollboxPostInput,
  TrollboxPostResponse,
} from "./techtree.js";

export interface JsonRpcRequest<T = unknown> {
  jsonrpc: "2.0";
  id: string;
  method: RegentRpcMethod;
  params?: T;
}

export interface JsonRpcSuccess<T = unknown> {
  jsonrpc: "2.0";
  id: string;
  result: T;
}

export interface JsonRpcFailure {
  jsonrpc: "2.0";
  id: string | null;
  error: {
    code: number;
    message: string;
    data?: unknown;
  };
}

export type JsonRpcResponse<T = unknown> = JsonRpcSuccess<T> | JsonRpcFailure;

export const REGENT_RPC_METHODS = {
  runtimePing: "runtime.ping",
  runtimeStatus: "runtime.status",
  runtimeShutdown: "runtime.shutdown",
  doctorRun: "doctor.run",
  doctorRunScoped: "doctor.runScoped",
  doctorRunFull: "doctor.runFull",
  authSiwaLogin: "auth.siwa.login",
  authSiwaLogout: "auth.siwa.logout",
  authSiwaStatus: "auth.siwa.status",
  techtreeStatus: "techtree.status",
  techtreeNodesList: "techtree.nodes.list",
  techtreeNodesGet: "techtree.nodes.get",
  techtreeNodesChildren: "techtree.nodes.children",
  techtreeNodesComments: "techtree.nodes.comments",
  techtreeActivityList: "techtree.activity.list",
  techtreeSearchQuery: "techtree.search.query",
  techtreeNodesWorkPacket: "techtree.nodes.workPacket",
  techtreeNodesCreate: "techtree.nodes.create",
  techtreeCommentsCreate: "techtree.comments.create",
  techtreeWatchCreate: "techtree.watch.create",
  techtreeWatchDelete: "techtree.watch.delete",
  techtreeWatchList: "techtree.watch.list",
  techtreeStarsCreate: "techtree.stars.create",
  techtreeStarsDelete: "techtree.stars.delete",
  techtreeInboxGet: "techtree.inbox.get",
  techtreeOpportunitiesList: "techtree.opportunities.list",
  techtreeTrollboxHistory: "techtree.trollbox.history",
  techtreeTrollboxPost: "techtree.trollbox.post",
  gossipsubStatus: "gossipsub.status",
  xmtpStatus: "xmtp.status",
} as const;

export type RegentRpcMethod = (typeof REGENT_RPC_METHODS)[keyof typeof REGENT_RPC_METHODS];

export interface RegentRpcParamsMap {
  "runtime.ping": undefined;
  "runtime.status": undefined;
  "runtime.shutdown": undefined;
  "doctor.run": DoctorRunParams | undefined;
  "doctor.runScoped": DoctorRunScopedParams;
  "doctor.runFull": DoctorRunFullParams | undefined;
  "auth.siwa.login": {
    walletAddress?: `0x${string}`;
    chainId?: number;
    registryAddress?: `0x${string}`;
    tokenId?: string;
    audience?: string;
  };
  "auth.siwa.logout": undefined;
  "auth.siwa.status": undefined;
  "techtree.status": undefined;
  "techtree.nodes.list": { limit?: number; seed?: string } | undefined;
  "techtree.nodes.get": { id: number };
  "techtree.nodes.children": { id: number; limit?: number };
  "techtree.nodes.comments": { id: number; limit?: number };
  "techtree.activity.list": { limit?: number } | undefined;
  "techtree.search.query": { q: string; limit?: number };
  "techtree.nodes.workPacket": { id: number };
  "techtree.nodes.create": NodeCreateInput;
  "techtree.comments.create": CommentCreateInput;
  "techtree.watch.create": { nodeId: number };
  "techtree.watch.delete": { nodeId: number };
  "techtree.watch.list": undefined;
  "techtree.stars.create": { nodeId: number };
  "techtree.stars.delete": { nodeId: number };
  "techtree.inbox.get": {
    cursor?: number;
    limit?: number;
    seed?: string;
    kind?: string | string[];
  } | undefined;
  "techtree.opportunities.list": Record<string, string | number | boolean | string[]> | undefined;
  "techtree.trollbox.history": { limit?: number; before?: number; room?: "global" | "agent" } | undefined;
  "techtree.trollbox.post": TrollboxPostInput;
  "gossipsub.status": undefined;
  "xmtp.status": undefined;
}

export interface RegentRpcResultMap {
  "runtime.ping": { ok: true };
  "runtime.status": RuntimeStatus;
  "runtime.shutdown": { ok: true };
  "doctor.run": DoctorReport;
  "doctor.runScoped": DoctorReport;
  "doctor.runFull": DoctorReport;
  "auth.siwa.login": SiwaVerifyResponse;
  "auth.siwa.logout": { ok: true };
  "auth.siwa.status": AuthStatusResponse;
  "techtree.status": {
    config: RegentConfig["techtree"];
    health: Record<string, unknown>;
  };
  "techtree.nodes.list": { data: TreeNode[] };
  "techtree.nodes.get": { data: TreeNode };
  "techtree.nodes.children": { data: TreeNode[] };
  "techtree.nodes.comments": { data: TreeComment[] };
  "techtree.activity.list": ActivityListResponse;
  "techtree.search.query": SearchResponse;
  "techtree.nodes.workPacket": { data: WorkPacketResponse };
  "techtree.nodes.create": NodeCreateResponse;
  "techtree.comments.create": CommentCreateResponse;
  "techtree.watch.create": { data: WatchRecord };
  "techtree.watch.delete": { ok: true };
  "techtree.watch.list": { data: WatchRecord[] };
  "techtree.stars.create": { data: NodeStarRecord };
  "techtree.stars.delete": { ok: true };
  "techtree.inbox.get": AgentInboxResponse;
  "techtree.opportunities.list": AgentOpportunitiesResponse;
  "techtree.trollbox.history": TrollboxListResponse;
  "techtree.trollbox.post": TrollboxPostResponse;
  "gossipsub.status": GossipsubStatus;
  "xmtp.status": XmtpStatus;
}

export type RegentRpcParams<TMethod extends RegentRpcMethod> = RegentRpcParamsMap[TMethod];
export type RegentRpcResult<TMethod extends RegentRpcMethod> = RegentRpcResultMap[TMethod];
