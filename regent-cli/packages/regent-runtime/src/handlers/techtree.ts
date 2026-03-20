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
  TrollboxListResponse,
  TrollboxPostInput,
  TrollboxPostResponse,
  TreeComment,
  TreeNode,
  WatchRecord,
  WorkPacketResponse,
} from "@regent/types";

import type { RuntimeContext } from "../runtime.js";

export async function handleTechtreeStatus(ctx: RuntimeContext): Promise<{
  config: typeof ctx.config.techtree;
  health: Record<string, unknown>;
}> {
  return {
    config: ctx.config.techtree,
    health: await ctx.techtree.health(),
  };
}

export async function handleTechtreeNodesList(
  ctx: RuntimeContext,
  params?: { limit?: number; seed?: string },
): Promise<{ data: TreeNode[] }> {
  return ctx.techtree.listNodes(params);
}

export async function handleTechtreeNodeGet(
  ctx: RuntimeContext,
  params: { id: number },
): Promise<{ data: TreeNode }> {
  return ctx.techtree.getNode(params.id);
}

export async function handleTechtreeNodeChildren(
  ctx: RuntimeContext,
  params: { id: number; limit?: number },
): Promise<{ data: TreeNode[] }> {
  return ctx.techtree.getChildren(params.id, { limit: params.limit });
}

export async function handleTechtreeNodeComments(
  ctx: RuntimeContext,
  params: { id: number; limit?: number },
): Promise<{ data: TreeComment[] }> {
  return ctx.techtree.getComments(params.id, { limit: params.limit });
}

export async function handleTechtreeActivityList(
  ctx: RuntimeContext,
  params?: { limit?: number },
): Promise<ActivityListResponse> {
  return ctx.techtree.listActivity(params);
}

export async function handleTechtreeSearchQuery(
  ctx: RuntimeContext,
  params: { q: string; limit?: number },
): Promise<SearchResponse> {
  return ctx.techtree.search(params);
}

export async function handleTechtreeNodeWorkPacket(
  ctx: RuntimeContext,
  params: { id: number },
): Promise<{ data: WorkPacketResponse }> {
  return ctx.techtree.getWorkPacket(params.id);
}

export async function handleTechtreeNodeCreate(
  ctx: RuntimeContext,
  params: NodeCreateInput,
): Promise<NodeCreateResponse> {
  return ctx.techtree.createNode(params);
}

export async function handleTechtreeCommentCreate(
  ctx: RuntimeContext,
  params: CommentCreateInput,
): Promise<CommentCreateResponse> {
  return ctx.techtree.createComment(params);
}

export async function handleTechtreeWatchCreate(
  ctx: RuntimeContext,
  params: { nodeId: number },
): Promise<{ data: WatchRecord }> {
  return ctx.techtree.watchNode(params.nodeId);
}

export async function handleTechtreeWatchDelete(
  ctx: RuntimeContext,
  params: { nodeId: number },
): Promise<{ ok: true }> {
  return ctx.techtree.unwatchNode(params.nodeId);
}

export async function handleTechtreeWatchList(
  ctx: RuntimeContext,
): Promise<{ data: WatchRecord[] }> {
  return ctx.techtree.listWatches();
}

export async function handleTechtreeStarCreate(
  ctx: RuntimeContext,
  params: { nodeId: number },
): Promise<{ data: NodeStarRecord }> {
  return ctx.techtree.starNode(params.nodeId);
}

export async function handleTechtreeStarDelete(
  ctx: RuntimeContext,
  params: { nodeId: number },
): Promise<{ ok: true }> {
  return ctx.techtree.unstarNode(params.nodeId);
}

export async function handleTechtreeInboxGet(
  ctx: RuntimeContext,
  params?: { cursor?: number; limit?: number; seed?: string; kind?: string | string[] },
): Promise<AgentInboxResponse> {
  return ctx.techtree.getInbox(params);
}

export async function handleTechtreeOpportunitiesList(
  ctx: RuntimeContext,
  params?: Record<string, string | number | boolean | string[]>,
): Promise<AgentOpportunitiesResponse> {
  return ctx.techtree.getOpportunities(params);
}

export async function handleTechtreeTrollboxHistory(
  ctx: RuntimeContext,
  params?: { before?: number; limit?: number; room?: "global" | "agent" },
): Promise<TrollboxListResponse> {
  return ctx.techtree.listTrollboxMessages(params);
}

export async function handleTechtreeTrollboxPost(
  ctx: RuntimeContext,
  params: TrollboxPostInput,
): Promise<TrollboxPostResponse> {
  return ctx.techtree.createAgentTrollboxMessage(params);
}
