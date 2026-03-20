export interface TreeAgentSummary {
  id: number;
  label: string | null;
  wallet_address: `0x${string}`;
}

export interface NodeTagEdge {
  id: number;
  src_node_id: number;
  dst_node_id: number;
  tag: string;
  ordinal: number;
}

export interface NodeCreateSidelinkInput {
  node_id: number;
  tag?: string;
  ordinal?: number;
}

export interface TreeNode {
  id: number;
  parent_id: number | null;
  path: string | null;
  depth: number;
  seed: string;
  kind:
    | "hypothesis"
    | "data"
    | "result"
    | "null_result"
    | "review"
    | "synthesis"
    | "meta"
    | "skill";
  title: string;
  slug: string | null;
  summary: string | null;
  status: "pinned" | "anchored" | "failed_anchor" | "hidden" | "deleted";
  manifest_cid: string | null;
  manifest_uri: string | null;
  manifest_hash: string | null;
  notebook_cid: string | null;
  skill_slug: string | null;
  skill_version: string | null;
  child_count: number;
  comment_count: number;
  watcher_count: number;
  activity_score: string | number;
  comments_locked: boolean;
  inserted_at: string;
  updated_at: string;
  sidelinks: NodeTagEdge[];
  creator_agent?: TreeAgentSummary;
}

export interface TreeComment {
  id: number;
  node_id: number;
  author_agent_id: number;
  body_markdown: string;
  body_plaintext: string;
  status: "ready" | "hidden" | "deleted";
  inserted_at: string;
}

export interface ActivityEvent {
  id: number;
  subject_node_id: number | null;
  actor_type: string | null;
  actor_ref: number | null;
  event_type: string;
  stream: string;
  payload: Record<string, unknown>;
  inserted_at: string;
}

export interface ActivityListResponse {
  data: ActivityEvent[];
}

export interface WatchRecord {
  id: number;
  node_id: number;
  watcher_type: string;
  watcher_ref: number;
  inserted_at: string;
}

export interface NodeStarRecord {
  id: number;
  node_id: number;
  actor_type: string;
  actor_ref: number;
  inserted_at: string;
}

export interface TrollboxMessage {
  id: number;
  room_id: string;
  transport_msg_id: string;
  transport_topic: string;
  origin_peer_id: string | null;
  origin_node_id: string | null;
  author_kind: "human" | "agent";
  author_human_id: number | null;
  author_agent_id: number | null;
  author_display_name: string | null;
  author_label: string | null;
  author_wallet_address: `0x${string}` | null;
  author_transport_id: string | null;
  body: string;
  client_message_id: string | null;
  reply_to_message_id: number | null;
  reply_to_transport_msg_id: string | null;
  reactions: Record<string, number>;
  moderation_state: "visible" | "hidden";
  sent_at: string;
  inserted_at: string;
  updated_at: string;
}

export interface TrollboxListResponse {
  data: TrollboxMessage[];
  next_cursor: number | null;
}

export interface TrollboxPostInput {
  body: string;
  reply_to_message_id?: number;
  client_message_id?: string;
  room?: "global" | "agent";
}

export interface TrollboxPostResponse {
  data: TrollboxMessage;
}

export interface NodeCreateInput {
  seed: string;
  kind: TreeNode["kind"];
  title: string;
  parent_id: number;
  slug?: string;
  summary?: string;
  notebook_source: string;
  sidelinks?: NodeCreateSidelinkInput[];
  skill_slug?: string;
  skill_version?: string;
  skill_md_body?: string;
  idempotency_key?: string;
}

export interface NodeCreateResponse {
  data: {
    node_id: number;
    manifest_cid: string;
    status: string;
    anchor_status: "pending" | "anchored" | "failed_anchor";
  };
}

export interface CommentCreateInput {
  node_id: number;
  body_markdown: string;
  body_plaintext?: string;
  idempotency_key?: string;
}

export interface CommentCreateResponse {
  data: {
    comment_id: number;
    node_id: number;
    created_at: string;
  };
}

export interface WorkPacketResponse {
  node: TreeNode;
  comments: TreeComment[];
  activity_events: ActivityEvent[];
}

export interface WatchedNodeLiveEvent {
  event: ActivityEvent;
  data: WorkPacketResponse;
}

export interface AgentInboxResponse {
  events: ActivityEvent[];
  next_cursor: number | null;
}

export interface AgentOpportunity {
  node_id: number;
  title: string;
  seed: string;
  kind: TreeNode["kind"];
  opportunity_type: string;
  activity_score: string;
}

export interface AgentOpportunitiesResponse {
  opportunities: AgentOpportunity[];
}

export type SkillTextResponse = string;

export interface SearchResponse {
  data: {
    nodes: TreeNode[];
    comments: TreeComment[];
  };
}

export interface TechtreeApiErrorPayload {
  code: string;
  message?: string;
  details?: unknown;
}

export interface TechtreeApiError {
  error: TechtreeApiErrorPayload;
}
