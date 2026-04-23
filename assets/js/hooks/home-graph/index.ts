import type { Hook, HookContext } from "phoenix_live_view";

import { animate } from "animejs";
import {
  Deck,
  OrthographicView,
  type PickingInfo,
} from "@deck.gl/core";
import { LineLayer, ScatterplotLayer } from "@deck.gl/layers";
import {
  ensureGraphAffordance,
  graphAffordances,
  type ActivityPulse,
  type ActivityTrace,
  type GraphActivityEvent,
  type GraphFocusSetsAffordance,
  type GraphThemeAffordance,
  type GraphViewportMode as GraphAffordanceViewportMode,
} from "./affordances";
import {
  type AnimationHandle,
  clamp,
  parseJson,
  pauseMotion,
  readBool,
  readNodeId,
  variantForNode,
} from "../home-shared";

type NodeStatus = "success" | "null" | "failed" | "pending";
type SubtreeMode = "children" | "descendants";
type GraphViewportMode = GraphAffordanceViewportMode;

type GraphNode = {
  id: number;
  label: string;
  title: string;
  x: number;
  y: number;
  depth: number;
  parent_id: number | null;
  parent_ids: number[];
  child_ids: number[];
  agent_id: number | null;
  agent_label: string | null;
  agent_wallet_address?: string | null;
  creator_address?: string | null;
  result_status: NodeStatus;
  score?: number;
  comment_count?: number;
  created_at?: number | null;
  is_comment?: boolean;
  kind: string;
  seed: string;
  path?: string | null;
  summary?: string | null;
  child_count: number;
  watcher_count: number;
};

type GraphEdge = {
  id: string;
  source_id: number;
  target_id: number;
  source: [number, number];
  target: [number, number];
  kind: "tree" | "citation" | "comment" | "derived";
};

type GraphPayload = {
  nodes: GraphNode[];
  edges: GraphEdge[];
  meta: {
    revision: number;
    layout_mode: string;
  };
};

type FocusState = {
  selected_node_id?: number | null;
  selected_agent_id?: number | null;
  subtree_root_id?: number | null;
  subtree_mode?: SubtreeMode | null;
  show_null_results?: boolean;
  filter_to_null_results?: boolean;
};

type GraphTheme = {
  edge: [number, number, number];
  node: [number, number, number];
  nodeAlt: [number, number, number];
  hover: [number, number, number];
  selected: [number, number, number];
  background: [number, number, number];
};

type GraphIndexes = {
  nodeById: Map<number, GraphNode>;
  parentById: Map<number, number | null>;
  childrenById: Map<number, number[]>;
  descendantsById: Map<number, Set<number>>;
  nodesByAgentId: Map<number, Set<number>>;
  nullResultNodeIds: Set<number>;
};

type FocusSets = {
  selectedNodeId: number | null;
  lineageNodeIds: Set<number>;
  agentNodeIds: Set<number>;
  subtreeNodeIds: Set<number>;
  nullNodeIds: Set<number>;
};

type GraphTransition = {
  progress: number;
};

type SeedBeacon = {
  id: string;
  seed: string;
  label: string;
  x: number;
  y: number;
  watcher_count: number;
  node_count: number;
};

type SeedTrunkSegment = {
  id: string;
  seed: string;
  source: [number, number];
  target: [number, number];
  watcher_count: number;
};

type GraphSearchIndexEntry = {
  id: string;
  kind: "node" | "agent";
  label: string;
  subtitle: string;
  nodeIds: number[];
  nodeId?: number;
  agentId?: number | null;
  exactPrimary: string[];
  exactSecondary: string[];
  prefixTerms: string[];
  fallbackTerms: string[];
  score: number;
};

type GraphSearchMatch = {
  entry: GraphSearchIndexEntry;
  rank: [number, number, number, string];
};

type GraphChrome = {
  modeChip: HTMLElement | null;
  watchChip: HTMLElement | null;
  palette: HTMLElement | null;
  paletteInput: HTMLInputElement | null;
  paletteResults: HTMLElement | null;
};

type GraphRuntime = {
  host: HTMLElement;
  deckRoot: HTMLDivElement;
  labelRoot: HTMLDivElement;
  tooltip: HTMLDivElement | null;
  deck: Deck<any>;
  pushEvent: (event: string, payload?: Record<string, unknown>) => void;
  payload: GraphPayload;
  indexes: GraphIndexes;
  focusState: FocusState;
  active: boolean;
  theme: GraphTheme;
  themeObserver: MutationObserver;
  resizeObserver: ResizeObserver;
  transition: GraphTransition;
  motion: AnimationHandle | null;
  viewMotion: AnimationHandle | null;
  sourcePositions: Map<number, { x: number; y: number }>;
  targetPositions: Map<number, { x: number; y: number }>;
  viewState: {
    target: [number, number, number];
    zoom: number;
  };
  chrome: GraphChrome;
  hoveredNodeId: number | null;
  activityEvents: GraphActivityEvent[];
  activityNow: number;
  tickTimer: number | null;
  activityAffordanceLoading: Promise<void> | null;
  labelsAffordanceLoading: Promise<void> | null;
  pendingActivityDiff:
    | {
        previousPayload: GraphPayload;
        nextPayload: GraphPayload;
        now: number;
      }
    | null;
  searchIndex: GraphSearchIndexEntry[];
  paletteOpen: boolean;
  paletteQuery: string;
  paletteSelectedIndex: number;
  onHostClick: (event: MouseEvent) => void;
  onHostInput: (event: Event) => void;
  onWindowKeyDown: (event: KeyboardEvent) => void;
};

type GraphHook = HookContext &
  Hook & {
    __graph?: GraphRuntime;
  };

const GRAPH_ACTIVITY_TTL_MS = 12_000;
const GRAPH_TICK_MS = 120;
const GRAPH_WATCH_THRESHOLD = -0.35;
const GRAPH_INSPECT_THRESHOLD = 0.9;
const GRAPH_VIEW_PADDING = 120;
const MIN_WORLD_SPAN = 0.24;
const MIN_WORLD_ZOOM = -2;
const MAX_WORLD_ZOOM = 12;

const defaultPayload: GraphPayload = {
  nodes: [],
  edges: [],
  meta: {
    revision: 0,
    layout_mode: "atlas",
  },
};

const defaultFocus: FocusState = {
  selected_node_id: null,
  selected_agent_id: null,
  subtree_root_id: null,
  subtree_mode: null,
  show_null_results: false,
  filter_to_null_results: false,
};

const defaultViewState: { target: [number, number, number]; zoom: number } = {
  target: [0, 0, 0],
  zoom: 0,
};

function mix(from: number, to: number, progress: number): number {
  return from + (to - from) * progress;
}

function normalizeSearchTerm(value: string | null | undefined): string {
  return (value || "").trim().toLowerCase();
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function hexToRgb(value: string, fallback: [number, number, number]): [number, number, number] {
  const normalized = value.trim().replace("#", "");
  const safe =
    normalized.length === 3
      ? normalized
          .split("")
          .map((part) => `${part}${part}`)
          .join("")
      : normalized.padEnd(6, "0").slice(0, 6);

  const red = Number.parseInt(safe.slice(0, 2), 16);
  const green = Number.parseInt(safe.slice(2, 4), 16);
  const blue = Number.parseInt(safe.slice(4, 6), 16);

  return Number.isFinite(red) && Number.isFinite(green) && Number.isFinite(blue)
    ? [red, green, blue]
    : fallback;
}

function readCssVar(styles: CSSStyleDeclaration, name: string, fallback: string): string {
  const value = styles.getPropertyValue(name).trim();
  return value || fallback;
}

function resolveGraphTheme(host: HTMLElement): GraphTheme {
  const styles = getComputedStyle(host);

  return {
    edge: hexToRgb(readCssVar(styles, "--fp-graph-edge", "#0c1120"), [12, 17, 32]),
    node: hexToRgb(readCssVar(styles, "--fp-graph-node", "#114ca7"), [17, 76, 167]),
    nodeAlt: hexToRgb(readCssVar(styles, "--fp-graph-node-alt", "#05070d"), [5, 7, 13]),
    hover: hexToRgb(readCssVar(styles, "--fp-graph-hover", "#fffdf6"), [255, 253, 246]),
    selected: hexToRgb(readCssVar(styles, "--fp-graph-selected", "#d4b15b"), [212, 177, 91]),
    background: hexToRgb(readCssVar(styles, "--fp-graph-background", "#fbf5e3"), [251, 245, 227]),
  };
}

function withAlpha(
  color: [number, number, number],
  alpha: number,
): [number, number, number, number] {
  return [color[0], color[1], color[2], clamp(alpha, 0, 255)];
}

function graphViewportModeForZoom(zoom: number): GraphViewportMode {
  if (zoom < GRAPH_WATCH_THRESHOLD) return "watch";
  if (zoom < GRAPH_INSPECT_THRESHOLD) return "navigate";
  return "inspect";
}

function lookupChrome(host: HTMLElement): GraphChrome {
  return {
    modeChip: host.querySelector<HTMLElement>("[data-graph-mode-chip]"),
    watchChip: host.querySelector<HTMLElement>("[data-graph-watch-chip]"),
    palette: host.querySelector<HTMLElement>("[data-graph-palette]"),
    paletteInput: host.querySelector<HTMLInputElement>("[data-graph-palette-input]"),
    paletteResults: host.querySelector<HTMLElement>("[data-graph-palette-results]"),
  };
}

function ensureLabelRoot(host: HTMLElement): HTMLDivElement {
  const existing = host.querySelector<HTMLDivElement>("[data-graph-node-label-root]");
  if (existing) return existing;

  const root = document.createElement("div");
  root.className = "fp-graph-node-labels";
  root.dataset.graphNodeLabelRoot = "";
  root.dataset.visible = "false";
  host.appendChild(root);
  return root;
}

function buildIndexes(payload: GraphPayload): GraphIndexes {
  const nodeById = new Map<number, GraphNode>(payload.nodes.map((node) => [node.id, node]));
  const parentById = new Map<number, number | null>();
  const childrenById = new Map<number, number[]>();
  const nodesByAgentId = new Map<number, Set<number>>();
  const nullResultNodeIds = new Set<number>();

  for (const node of payload.nodes) {
    parentById.set(node.id, node.parent_id);
    childrenById.set(node.id, [...node.child_ids]);

    if (node.agent_id != null) {
      const group = nodesByAgentId.get(node.agent_id) ?? new Set<number>();
      group.add(node.id);
      nodesByAgentId.set(node.agent_id, group);
    }

    if (node.result_status === "null") {
      nullResultNodeIds.add(node.id);
    }
  }

  const descendantsById = new Map<number, Set<number>>();

  const visit = (nodeId: number): Set<number> => {
    const cached = descendantsById.get(nodeId);
    if (cached) return cached;

    const descendants = new Set<number>();

    for (const childId of childrenById.get(nodeId) ?? []) {
      descendants.add(childId);
      for (const nestedId of visit(childId)) {
        descendants.add(nestedId);
      }
    }

    descendantsById.set(nodeId, descendants);
    return descendants;
  };

  for (const node of payload.nodes) {
    visit(node.id);
  }

  return {
    nodeById,
    parentById,
    childrenById,
    descendantsById,
    nodesByAgentId,
    nullResultNodeIds,
  };
}

function mergeFocusState(host: HTMLElement, focusState: FocusState): FocusState {
  const selectedNodeId = readNodeId(host.dataset.selectedNodeId);

  return {
    ...defaultFocus,
    ...focusState,
    selected_node_id: selectedNodeId ?? focusState.selected_node_id ?? null,
  };
}

function focusSetsFor(indexes: GraphIndexes, focusState: FocusState): FocusSets {
  const selectedNodeId = focusState.selected_node_id ?? null;
  const lineageNodeIds = new Set<number>();
  const agentNodeIds =
    focusState.selected_agent_id != null
      ? new Set(indexes.nodesByAgentId.get(focusState.selected_agent_id) ?? [])
      : new Set<number>();
  const subtreeNodeIds = new Set<number>();

  let cursor = selectedNodeId;
  while (cursor != null && !lineageNodeIds.has(cursor)) {
    lineageNodeIds.add(cursor);
    cursor = indexes.parentById.get(cursor) ?? null;
  }

  if (focusState.subtree_root_id != null) {
    const rootId = focusState.subtree_root_id;
    const targets =
      focusState.subtree_mode === "children"
        ? indexes.childrenById.get(rootId) ?? []
        : Array.from(indexes.descendantsById.get(rootId) ?? []);

    for (const nodeId of targets) {
      subtreeNodeIds.add(nodeId);
    }
  }

  return {
    selectedNodeId,
    lineageNodeIds,
    agentNodeIds,
    subtreeNodeIds,
    nullNodeIds: indexes.nullResultNodeIds,
  };
}

function nodeImportance(node: GraphNode): number {
  const score = node.score ?? node.watcher_count ?? 0;
  return 6 + Math.min(score, 16) * 0.45 + Math.max(0, 3 - node.depth) * 1.2;
}

function nodeVisible(node: GraphNode, focusState: FocusState): boolean {
  return !focusState.filter_to_null_results || node.result_status === "null";
}

function hasPinnedFocus(focusSets: FocusSets, focusState: FocusState): boolean {
  return (
    focusSets.selectedNodeId != null ||
    focusSets.lineageNodeIds.size > 0 ||
    focusSets.agentNodeIds.size > 0 ||
    focusSets.subtreeNodeIds.size > 0 ||
    focusState.show_null_results === true ||
    focusState.filter_to_null_results === true
  );
}

function visibleBaseNodes(
  nodes: GraphNode[],
  focusSets: FocusSets,
  focusState: FocusState,
  mode: GraphViewportMode,
): GraphNode[] {
  const visible = nodes.filter((node) => nodeVisible(node, focusState));

  if (mode !== "watch") return visible;
  if (!hasPinnedFocus(focusSets, focusState)) return [];

  return visible.filter(
    (node) =>
      node.id === focusSets.selectedNodeId ||
      focusSets.lineageNodeIds.has(node.id) ||
      focusSets.agentNodeIds.has(node.id) ||
      focusSets.subtreeNodeIds.has(node.id),
  );
}

function visibleBaseEdges(
  edges: GraphEdge[],
  indexes: GraphIndexes,
  focusSets: FocusSets,
  focusState: FocusState,
  mode: GraphViewportMode,
): GraphEdge[] {
  if (mode !== "watch") {
    return edges.filter((edge) => edgeVisible(edge, indexes, focusState));
  }

  if (!hasPinnedFocus(focusSets, focusState)) return [];

  return edges.filter((edge) => {
    if (!edgeVisible(edge, indexes, focusState)) return false;

    return (
      edge.source_id === focusSets.selectedNodeId ||
      edge.target_id === focusSets.selectedNodeId ||
      (focusSets.lineageNodeIds.has(edge.source_id) &&
        focusSets.lineageNodeIds.has(edge.target_id)) ||
      (focusSets.subtreeNodeIds.has(edge.source_id) &&
        focusSets.subtreeNodeIds.has(edge.target_id)) ||
      focusSets.agentNodeIds.has(edge.source_id) ||
      focusSets.agentNodeIds.has(edge.target_id)
    );
  });
}

function statusPhase(node: GraphNode, now: number): number {
  return (now / 900 + node.id * 0.13) % (Math.PI * 2);
}

function nodeFillColor(
  node: GraphNode,
  focusSets: FocusSets,
  focusState: FocusState,
  theme: GraphTheme,
  mode: GraphViewportMode,
  now: number,
): [number, number, number, number] {
  if (!nodeVisible(node, focusState)) {
    return withAlpha(theme.nodeAlt, 16);
  }

  const emphasisAlpha = mode === "watch" ? 210 : 245;

  if (focusSets.selectedNodeId === node.id) {
    return withAlpha(theme.selected, emphasisAlpha);
  }

  if (focusSets.lineageNodeIds.has(node.id)) {
    return withAlpha(theme.hover, mode === "watch" ? 180 : 228);
  }

  if (focusSets.subtreeNodeIds.has(node.id)) {
    return withAlpha(theme.hover, mode === "watch" ? 165 : 220);
  }

  if (focusSets.agentNodeIds.has(node.id)) {
    return withAlpha(theme.node, mode === "watch" ? 160 : 232);
  }

  if (focusState.show_null_results && focusSets.nullNodeIds.has(node.id)) {
    const alpha = 180 + Math.round(Math.sin(statusPhase(node, now)) * 32);
    return withAlpha(theme.selected, alpha);
  }

  if (node.result_status === "failed") {
    return [149, 44, 44, mode === "watch" ? 120 : 210];
  }

  if (node.result_status === "pending") {
    const alpha = 150 + Math.round(Math.sin(statusPhase(node, now)) * 28);
    return withAlpha(theme.nodeAlt, mode === "watch" ? alpha - 40 : alpha);
  }

  if (mode === "watch") {
    return variantForNode(node) === "alt"
      ? withAlpha(theme.nodeAlt, 54)
      : withAlpha(theme.node, 46);
  }

  return variantForNode(node) === "alt"
    ? withAlpha(theme.nodeAlt, 210)
    : withAlpha(theme.node, 205);
}

function nodeLineColor(
  node: GraphNode,
  focusSets: FocusSets,
  theme: GraphTheme,
  mode: GraphViewportMode,
): [number, number, number, number] {
  if (focusSets.selectedNodeId === node.id) return withAlpha(theme.hover, 255);
  if (focusSets.lineageNodeIds.has(node.id)) return withAlpha(theme.selected, 230);
  if (focusSets.subtreeNodeIds.has(node.id)) return withAlpha(theme.selected, 210);
  if (focusSets.agentNodeIds.has(node.id)) return withAlpha(theme.hover, 210);
  return withAlpha(theme.background, mode === "watch" ? 48 : 110);
}

function edgeVisible(edge: GraphEdge, indexes: GraphIndexes, focusState: FocusState): boolean {
  if (!focusState.filter_to_null_results) return true;
  const source = indexes.nodeById.get(edge.source_id);
  const target = indexes.nodeById.get(edge.target_id);
  return source?.result_status === "null" || target?.result_status === "null";
}

function edgeColor(
  edge: GraphEdge,
  indexes: GraphIndexes,
  focusSets: FocusSets,
  focusState: FocusState,
  theme: GraphTheme,
  mode: GraphViewportMode,
): [number, number, number, number] {
  if (!edgeVisible(edge, indexes, focusState)) return withAlpha(theme.edge, 18);

  const touchesSelected =
    edge.source_id === focusSets.selectedNodeId || edge.target_id === focusSets.selectedNodeId;
  const touchesLineage =
    focusSets.lineageNodeIds.has(edge.source_id) &&
    focusSets.lineageNodeIds.has(edge.target_id);
  const touchesSubtree =
    focusSets.subtreeNodeIds.has(edge.source_id) &&
    focusSets.subtreeNodeIds.has(edge.target_id);
  const touchesAgent =
    focusSets.agentNodeIds.has(edge.source_id) || focusSets.agentNodeIds.has(edge.target_id);
  const touchesNull =
    focusSets.nullNodeIds.has(edge.source_id) || focusSets.nullNodeIds.has(edge.target_id);

  if (touchesSelected) return withAlpha(theme.selected, 245);
  if (touchesLineage) return withAlpha(theme.selected, 210);
  if (touchesSubtree) return withAlpha(theme.hover, 190);
  if (touchesAgent) return withAlpha(theme.node, 172);
  if (focusState.show_null_results && touchesNull) return withAlpha(theme.selected, 170);

  if (mode === "watch") {
    return withAlpha(theme.edge, edge.kind === "tree" ? 18 : 8);
  }

  return withAlpha(theme.edge, edge.kind === "tree" ? 72 : 32);
}

function edgeWidth(edge: GraphEdge, focusSets: FocusSets, mode: GraphViewportMode): number {
  const touchesSelected =
    edge.source_id === focusSets.selectedNodeId || edge.target_id === focusSets.selectedNodeId;
  const touchesLineage =
    focusSets.lineageNodeIds.has(edge.source_id) &&
    focusSets.lineageNodeIds.has(edge.target_id);
  const touchesSubtree =
    focusSets.subtreeNodeIds.has(edge.source_id) &&
    focusSets.subtreeNodeIds.has(edge.target_id);
  const touchesAgent =
    focusSets.agentNodeIds.has(edge.source_id) || focusSets.agentNodeIds.has(edge.target_id);

  if (touchesSelected) return 4.5;
  if (touchesLineage) return 3.8;
  if (touchesSubtree) return 3;
  if (touchesAgent) return 2.5;
  return mode === "watch" ? 0.8 : edge.kind === "tree" ? 1.25 : 0.75;
}

function pruneActivityEvents(events: GraphActivityEvent[], now: number): GraphActivityEvent[] {
  return events.filter((event) => now - event.occurred_at <= GRAPH_ACTIVITY_TTL_MS);
}

function loadLabelsAffordance(runtime: GraphRuntime) {
  runtime.labelsAffordanceLoading =
    runtime.labelsAffordanceLoading ||
    ensureGraphAffordance("labels", "/assets/js/home-graph-labels.js")
      .then(() => {
        runtime.labelsAffordanceLoading = null;
        renderGraph(runtime);
      })
      .catch((error) => {
        runtime.labelsAffordanceLoading = null;
        console.error("Failed to load graph labels affordance", error);
      });
}

function syncPendingActivityDiff(runtime: GraphRuntime) {
  const activity = graphAffordances().activity;
  const pendingDiff = runtime.pendingActivityDiff;

  if (!activity || !pendingDiff) return;

  runtime.activityEvents = activity.diffActivityEvents({
    previousNodes: pendingDiff.previousPayload.nodes,
    nextNodes: pendingDiff.nextPayload.nodes,
    nextRevision: pendingDiff.nextPayload.meta.revision,
    existingEvents: runtime.activityEvents,
    now: pendingDiff.now,
  });
  runtime.pendingActivityDiff = null;
}

function loadActivityAffordance(runtime: GraphRuntime) {
  runtime.activityAffordanceLoading =
    runtime.activityAffordanceLoading ||
    ensureGraphAffordance("activity", "/assets/js/home-graph-activity.js")
      .then(() => {
        runtime.activityAffordanceLoading = null;
        syncPendingActivityDiff(runtime);
        renderGraph(runtime);
      })
      .catch((error) => {
        runtime.activityAffordanceLoading = null;
        console.error("Failed to load graph activity affordance", error);
      });
}

function graphThemeAffordance(theme: GraphTheme): GraphThemeAffordance {
  return theme;
}

function fitViewStateForNodes(
  nodes: Array<{ x: number; y: number }>,
  deckRoot: HTMLElement,
): { target: [number, number, number]; zoom: number } {
  const viewportWidth = Math.max(deckRoot.clientWidth - GRAPH_VIEW_PADDING * 2, 1);
  const viewportHeight = Math.max(deckRoot.clientHeight - GRAPH_VIEW_PADDING * 2, 1);

  if (nodes.length === 0) {
    return { ...defaultViewState };
  }

  let minX = Number.POSITIVE_INFINITY;
  let maxX = Number.NEGATIVE_INFINITY;
  let minY = Number.POSITIVE_INFINITY;
  let maxY = Number.NEGATIVE_INFINITY;

  for (const node of nodes) {
    minX = Math.min(minX, node.x);
    maxX = Math.max(maxX, node.x);
    minY = Math.min(minY, node.y);
    maxY = Math.max(maxY, node.y);
  }

  const width = Math.max(maxX - minX, MIN_WORLD_SPAN);
  const height = Math.max(maxY - minY, MIN_WORLD_SPAN);
  const scale = Math.max(Math.min(viewportWidth / width, viewportHeight / height), 0.01);

  return {
    target: [(minX + maxX) / 2, (minY + maxY) / 2, 0],
    zoom: clamp(Math.log2(scale), MIN_WORLD_ZOOM, MAX_WORLD_ZOOM),
  };
}

function fitViewStateForPayload(
  payload: GraphPayload,
  deckRoot: HTMLElement,
): { target: [number, number, number]; zoom: number } {
  return fitViewStateForNodes(payload.nodes, deckRoot);
}

function updateViewState(
  runtime: GraphRuntime,
  nextViewState: { target: [number, number, number]; zoom: number },
  options?: { animate?: boolean },
) {
  const shouldAnimate = options?.animate ?? false;
  pauseMotion(runtime.viewMotion);

  if (!shouldAnimate) {
    runtime.viewState.target = [...nextViewState.target];
    runtime.viewState.zoom = nextViewState.zoom;
    runtime.viewMotion = null;
    return;
  }

  const animatedView = {
    targetX: runtime.viewState.target[0],
    targetY: runtime.viewState.target[1],
    targetZ: runtime.viewState.target[2],
    zoom: runtime.viewState.zoom,
  };

  runtime.viewMotion = animate(animatedView, {
    targetX: nextViewState.target[0],
    targetY: nextViewState.target[1],
    targetZ: nextViewState.target[2],
    zoom: nextViewState.zoom,
    duration: 320,
    ease: "outCubic",
    onUpdate: () => {
      runtime.viewState.target = [animatedView.targetX, animatedView.targetY, animatedView.targetZ];
      runtime.viewState.zoom = animatedView.zoom;
      renderGraph(runtime);
    },
    onComplete: () => {
      runtime.viewMotion = null;
    },
  }) as AnimationHandle;
}

function fitGraphView(runtime: GraphRuntime, options?: { animate?: boolean }) {
  updateViewState(runtime, fitViewStateForPayload(runtime.payload, runtime.deckRoot), options);
}

function fitGraphToNodeIds(
  runtime: GraphRuntime,
  nodeIds: number[],
  options?: { animate?: boolean },
) {
  const uniqueIds = Array.from(new Set(nodeIds));
  const nodes = uniqueIds
    .map((nodeId) => runtime.payload.nodes.find((node) => node.id === nodeId))
    .filter((node): node is GraphNode => node != null);

  if (nodes.length === 0) return;
  updateViewState(runtime, fitViewStateForNodes(nodes, runtime.deckRoot), options);
}

function zoomGraphView(runtime: GraphRuntime, delta: number) {
  updateViewState(
    runtime,
    {
      target: [...runtime.viewState.target],
      zoom: clamp(runtime.viewState.zoom + delta, MIN_WORLD_ZOOM, MAX_WORLD_ZOOM),
    },
    { animate: true },
  );
}

function graphController(active: boolean) {
  if (!active) return false;

  return {
    dragPan: true,
    scrollZoom: true,
    touchZoom: true,
    doubleClickZoom: false,
    keyboard: false,
  };
}

function currentPositions(runtime: GraphRuntime): Map<number, { x: number; y: number }> {
  const positions = new Map<number, { x: number; y: number }>();
  const ids = new Set<number>([
    ...Array.from(runtime.sourcePositions.keys()),
    ...Array.from(runtime.targetPositions.keys()),
  ]);

  for (const id of ids) {
    const source = runtime.sourcePositions.get(id) ?? runtime.targetPositions.get(id) ?? { x: 0, y: 0 };
    const target = runtime.targetPositions.get(id) ?? source;

    positions.set(id, {
      x: mix(source.x, target.x, runtime.transition.progress),
      y: mix(source.y, target.y, runtime.transition.progress),
    });
  }

  return positions;
}

function interpolatedNodes(runtime: GraphRuntime): GraphNode[] {
  const positions = currentPositions(runtime);

  return runtime.payload.nodes.map((node) => {
    const position = positions.get(node.id);

    return position ? { ...node, x: position.x, y: position.y } : node;
  });
}

function hydrateEdges(
  edges: GraphEdge[],
  positions: Map<number, { x: number; y: number }>,
): GraphEdge[] {
  return edges.map((edge) => {
    const source = positions.get(edge.source_id);
    const target = positions.get(edge.target_id);

    return source && target
      ? {
          ...edge,
          source: [source.x, source.y],
          target: [target.x, target.y],
        }
      : edge;
  });
}

function setTooltip(runtime: GraphRuntime, node: GraphNode | null, info: PickingInfo<GraphNode>) {
  if (!runtime.tooltip) return;

  if (!node || info.x == null || info.y == null) {
    runtime.tooltip.removeAttribute("data-visible");
    runtime.tooltip.textContent = "";
    return;
  }

  runtime.tooltip.dataset.visible = "true";
  runtime.tooltip.textContent = `${node.seed} · ${node.label}`;
  runtime.tooltip.style.setProperty("--fp-tooltip-x", `${info.x}px`);
  runtime.tooltip.style.setProperty("--fp-tooltip-y", `${info.y}px`);
}

function deriveSeedBeacons(nodes: GraphNode[]): SeedBeacon[] {
  const groups = new Map<string, GraphNode[]>();

  for (const node of nodes) {
    const group = groups.get(node.seed) ?? [];
    group.push(node);
    groups.set(node.seed, group);
  }

  return Array.from(groups.entries()).map(([seed, seedNodes]) => {
    const sum = seedNodes.reduce(
      (acc, node) => ({
        x: acc.x + node.x,
        y: acc.y + node.y,
        watcher: acc.watcher + (node.watcher_count || 0),
      }),
      { x: 0, y: 0, watcher: 0 },
    );

    const root = seedNodes.find((node) => node.depth === 0) ?? seedNodes[0]!;

    return {
      id: `seed:${seed}`,
      seed,
      label: root.seed,
      x: sum.x / seedNodes.length,
      y: sum.y / seedNodes.length,
      watcher_count: sum.watcher,
      node_count: seedNodes.length,
    };
  });
}

function deriveSeedTrunkSegments(nodes: GraphNode[]): SeedTrunkSegment[] {
  const bySeed = new Map<string, Map<number, GraphNode[]>>();

  for (const node of nodes) {
    const byDepth = bySeed.get(node.seed) ?? new Map<number, GraphNode[]>();
    const group = byDepth.get(node.depth) ?? [];
    group.push(node);
    byDepth.set(node.depth, group);
    bySeed.set(node.seed, byDepth);
  }

  const segments: SeedTrunkSegment[] = [];

  for (const [seed, byDepth] of bySeed.entries()) {
    const averaged = Array.from(byDepth.entries())
      .sort((left, right) => left[0] - right[0])
      .map(([depth, depthNodes]) => {
        const sum = depthNodes.reduce(
          (acc, node) => ({
            x: acc.x + node.x,
            y: acc.y + node.y,
            watcher: acc.watcher + (node.watcher_count || 0),
          }),
          { x: 0, y: 0, watcher: 0 },
        );

        return {
          depth,
          x: sum.x / depthNodes.length,
          y: sum.y / depthNodes.length,
          watcher_count: sum.watcher / depthNodes.length,
        };
      });

    for (let index = 0; index < averaged.length - 1; index += 1) {
      const source = averaged[index]!;
      const target = averaged[index + 1]!;

      segments.push({
        id: `seed:${seed}:${source.depth}:${target.depth}`,
        seed,
        source: [source.x, source.y],
        target: [target.x, target.y],
        watcher_count: Math.max(source.watcher_count, target.watcher_count),
      });
    }
  }

  return segments;
}

function buildSearchIndex(payload: GraphPayload, indexes: GraphIndexes): GraphSearchIndexEntry[] {
  const nodeEntries = payload.nodes.map((node) => {
    const exactPrimary = [
      `${node.id}`,
      node.agent_wallet_address || "",
      node.creator_address || "",
    ]
      .map(normalizeSearchTerm)
      .filter(Boolean);
    const exactSecondary = [node.title, node.label, node.path || ""]
      .map(normalizeSearchTerm)
      .filter(Boolean);
    const prefixTerms = [
      node.title,
      node.label,
      node.path || "",
      `${node.id}`,
      node.seed,
      node.agent_label || "",
      node.agent_wallet_address || "",
      node.creator_address || "",
    ]
      .map(normalizeSearchTerm)
      .filter(Boolean);
    const fallbackTerms = [node.seed, node.agent_label || ""]
      .map(normalizeSearchTerm)
      .filter(Boolean);

    return {
      id: `node:${node.id}`,
      kind: "node" as const,
      label: node.label,
      subtitle: `${node.seed} · #${node.id}${node.path ? ` · ${node.path}` : ""}`,
      nodeIds: [node.id],
      nodeId: node.id,
      exactPrimary,
      exactSecondary,
      prefixTerms,
      fallbackTerms,
      score: nodeImportance(node),
    };
  });

  const agentEntries = Array.from(indexes.nodesByAgentId.entries()).map(([agentId, nodeIds]) => {
    const authoredNodes = Array.from(nodeIds)
      .map((nodeId) => indexes.nodeById.get(nodeId))
      .filter((node): node is GraphNode => node != null);
    const sample = authoredNodes[0];
    const wallet = sample?.agent_wallet_address || "";
    const label = sample?.agent_label || `Agent ${agentId}`;
    const exactPrimary = [`${agentId}`, wallet].map(normalizeSearchTerm).filter(Boolean);
    const exactSecondary = [label].map(normalizeSearchTerm).filter(Boolean);
    const prefixTerms = [label, `${agentId}`, wallet].map(normalizeSearchTerm).filter(Boolean);
    const fallbackTerms = [label, "agent", wallet].map(normalizeSearchTerm).filter(Boolean);

    return {
      id: `agent:${agentId}`,
      kind: "agent" as const,
      label,
      subtitle: wallet
        ? `${authoredNodes.length} authored nodes · ${wallet}`
        : `${authoredNodes.length} authored nodes`,
      nodeIds: Array.from(nodeIds),
      agentId,
      exactPrimary,
      exactSecondary,
      prefixTerms,
      fallbackTerms,
      score: authoredNodes.reduce((total, node) => total + nodeImportance(node), 0),
    };
  });

  return [...nodeEntries, ...agentEntries];
}

function matchingTermLength(terms: string[], query: string, predicate: (term: string) => boolean): number {
  return terms.reduce((best, term) => {
    if (!predicate(term)) return best;
    return Math.min(best, term.length);
  }, Number.POSITIVE_INFINITY);
}

function rankSearchEntry(entry: GraphSearchIndexEntry, query: string): [number, number, number, string] | null {
  if (query === "") {
    return [5, entry.kind === "node" ? 0 : 1, -entry.score, entry.label.toLowerCase()];
  }

  if (entry.exactPrimary.includes(query)) {
    return [0, entry.kind === "node" ? 0 : 1, -entry.score, entry.label.toLowerCase()];
  }

  if (entry.exactSecondary.includes(query)) {
    return [1, entry.kind === "node" ? 0 : 1, -entry.score, entry.label.toLowerCase()];
  }

  const prefixLength = matchingTermLength(entry.prefixTerms, query, (term) => term.startsWith(query));
  if (Number.isFinite(prefixLength)) {
    return [2, prefixLength, -entry.score, entry.label.toLowerCase()];
  }

  const substringLength = matchingTermLength(entry.prefixTerms, query, (term) => term.includes(query));
  if (Number.isFinite(substringLength)) {
    return [3, substringLength, -entry.score, entry.label.toLowerCase()];
  }

  const fallbackLength = matchingTermLength(entry.fallbackTerms, query, (term) => term.includes(query));
  if (Number.isFinite(fallbackLength)) {
    return [4, fallbackLength, -entry.score, entry.label.toLowerCase()];
  }

  return null;
}

function searchEntries(index: GraphSearchIndexEntry[], query: string): GraphSearchMatch[] {
  const normalized = normalizeSearchTerm(query);

  return index
    .map((entry) => {
      const rank = rankSearchEntry(entry, normalized);
      return rank ? { entry, rank } : null;
    })
    .filter((match): match is GraphSearchMatch => match != null)
    .sort((left, right) => {
      for (let index = 0; index < left.rank.length; index += 1) {
        if (left.rank[index] < right.rank[index]) return -1;
        if (left.rank[index] > right.rank[index]) return 1;
      }

      return 0;
    })
    .slice(0, 8);
}

function renderPalette(runtime: GraphRuntime) {
  const { palette, paletteInput, paletteResults } = runtime.chrome;
  if (!palette || !paletteInput || !paletteResults) return;

  const results = runtime.paletteOpen ? searchEntries(runtime.searchIndex, runtime.paletteQuery) : [];
  if (results.length === 0) {
    runtime.paletteSelectedIndex = 0;
  } else {
    runtime.paletteSelectedIndex = clamp(runtime.paletteSelectedIndex, 0, results.length - 1);
  }

  palette.dataset.open = runtime.paletteOpen ? "true" : "false";
  palette.setAttribute("aria-hidden", runtime.paletteOpen ? "false" : "true");
  palette.toggleAttribute("hidden", !runtime.paletteOpen);

  if (!runtime.paletteOpen) return;

  if (paletteInput.value !== runtime.paletteQuery) {
    paletteInput.value = runtime.paletteQuery;
  }

  if (results.length === 0) {
    paletteResults.innerHTML = `
      <div class="fp-graph-palette-empty">
        <p class="font-display">No frontier match</p>
        <p class="font-body">Try a node id, wallet, seed, label, or path segment.</p>
      </div>
    `;
    return;
  }

  paletteResults.innerHTML = results
    .map((match, index) => {
      const isSelected = index === runtime.paletteSelectedIndex;
      return `
        <button
          type="button"
          class="fp-graph-palette-result${isSelected ? " is-selected" : ""}"
          data-graph-palette-action="result"
          data-graph-palette-result-index="${index}"
          aria-selected="${isSelected ? "true" : "false"}"
        >
          <span class="fp-graph-palette-result-meta font-display">${match.entry.kind}</span>
          <span class="fp-graph-palette-result-copy">
            <strong class="font-display">${escapeHtml(match.entry.label)}</strong>
            <span class="font-body">${escapeHtml(match.entry.subtitle)}</span>
          </span>
        </button>
      `;
    })
    .join("");
}

function openPalette(runtime: GraphRuntime, query = "") {
  if (!runtime.active) return;

  runtime.chrome = lookupChrome(runtime.host);
  runtime.paletteOpen = true;
  runtime.paletteQuery = query;
  runtime.paletteSelectedIndex = 0;
  renderPalette(runtime);

  requestAnimationFrame(() => {
    runtime.chrome.paletteInput?.focus();
    runtime.chrome.paletteInput?.select();
  });
}

function closePalette(runtime: GraphRuntime) {
  runtime.paletteOpen = false;
  renderPalette(runtime);
}

function currentPaletteResults(runtime: GraphRuntime): GraphSearchMatch[] {
  return searchEntries(runtime.searchIndex, runtime.paletteQuery);
}

function nodeNeighborhoodIds(indexes: GraphIndexes, nodeId: number): number[] {
  return uniqueNodeIds([
    nodeId,
    indexes.parentById.get(nodeId) ?? null,
    ...(indexes.childrenById.get(nodeId) ?? []),
  ]);
}

function uniqueNodeIds(values: Array<number | null | undefined>): number[] {
  return Array.from(
    new Set(
      values.filter((value): value is number => typeof value === "number" && Number.isFinite(value)),
    ),
  );
}

function updateChrome(runtime: GraphRuntime, mode: GraphViewportMode) {
  runtime.host.dataset.graphMode = mode;

  if (runtime.chrome.modeChip) {
    runtime.chrome.modeChip.textContent =
      mode === "watch" ? "Watch mode" : mode === "navigate" ? "Navigate mode" : "Inspect mode";
  }

  if (runtime.chrome.watchChip) {
    runtime.chrome.watchChip.hidden = mode !== "watch";
  }
}

function selectSearchMatch(
  runtime: GraphRuntime,
  match: GraphSearchMatch,
  pinFocus: boolean,
) {
  closePalette(runtime);

  if (match.entry.kind === "agent" && match.entry.agentId != null) {
    fitGraphToNodeIds(runtime, match.entry.nodeIds, { animate: true });

    if (!pinFocus) {
      renderGraph(runtime);
      return;
    }

    runtime.focusState = {
      ...defaultFocus,
      selected_agent_id: match.entry.agentId,
    };
    renderGraph(runtime);
    runtime.pushEvent("clear-graph-focus", {});
    runtime.pushEvent("focus-agent", { agent_id: match.entry.agentId });
    return;
  }

  const nodeId = match.entry.nodeId;
  if (nodeId == null) return;

  fitGraphToNodeIds(runtime, nodeNeighborhoodIds(runtime.indexes, nodeId), { animate: true });

  if (!pinFocus) {
    renderGraph(runtime);
    return;
  }

  runtime.focusState = {
    ...defaultFocus,
    selected_node_id: nodeId,
    subtree_root_id: nodeId,
    subtree_mode: "children",
  };
  renderGraph(runtime);

  animate(runtime.host, {
    scale: [0.996, 1],
    duration: 180,
    ease: "outCubic",
  });

  runtime.pushEvent("clear-graph-focus", {});
  runtime.pushEvent("select-node", { node_id: nodeId });
  runtime.pushEvent("focus-subtree", { mode: "children", node_id: nodeId });
}

function buildLayers(runtime: GraphRuntime) {
  const focusState = mergeFocusState(runtime.host, runtime.focusState);
  const focusSets = focusSetsFor(runtime.indexes, focusState);
  const mode = graphViewportModeForZoom(runtime.viewState.zoom);
  const positions = currentPositions(runtime);
  const allNodes = interpolatedNodes(runtime);
  const baseNodes = visibleBaseNodes(allNodes, focusSets, focusState, mode);
  const baseEdges = visibleBaseEdges(
    hydrateEdges(runtime.payload.edges, positions),
    runtime.indexes,
    focusSets,
    focusState,
    mode,
  );
  const seedBeacons = deriveSeedBeacons(allNodes);
  const seedTrunks = deriveSeedTrunkSegments(allNodes);
  const activityAffordance = graphAffordances().activity;
  const labelsAffordance = graphAffordances().labels;

  if (!labelsAffordance && runtime.active && mode === "inspect") {
    loadLabelsAffordance(runtime);
  }

  const activityData = activityAffordance
    ? activityAffordance.deriveActivityLayerData({
        events: pruneActivityEvents(runtime.activityEvents, runtime.activityNow),
        indexes: runtime.indexes,
        positions,
        theme: graphThemeAffordance(runtime.theme),
        now: runtime.activityNow,
      })
    : { traces: [] as ActivityTrace[], glows: [] as ActivityPulse[], rings: [] as ActivityPulse[] };
  const statusPulses = activityAffordance
    ? activityAffordance.deriveStatusPulseNodes({
        nodes: allNodes,
        focusState,
        mode,
        now: runtime.activityNow,
        theme: graphThemeAffordance(runtime.theme),
      })
    : [];
  if (labelsAffordance) {
    labelsAffordance.renderLabels({
      nodes: baseNodes,
      focusSets: focusSets as GraphFocusSetsAffordance,
      focusState,
      mode,
      theme: graphThemeAffordance(runtime.theme),
      root: runtime.labelRoot,
      viewState: runtime.viewState,
      viewport: {
        width: runtime.deckRoot.clientWidth,
        height: runtime.deckRoot.clientHeight,
      },
    });
  } else {
    runtime.labelRoot.replaceChildren();
    runtime.labelRoot.dataset.visible = "false";
  }

  updateChrome(runtime, mode);

  return [
    ...(mode === "watch"
      ? [
          new LineLayer<SeedTrunkSegment>({
            id: "frontpage-seed-trunks",
            data: seedTrunks,
            getSourcePosition: (segment) => segment.source,
            getTargetPosition: (segment) => segment.target,
            getColor: () => withAlpha(runtime.theme.edge, 44),
            getWidth: (segment) => 1.5 + Math.min(segment.watcher_count / 18, 2.2),
            widthUnits: "pixels",
          }),
          new ScatterplotLayer<SeedBeacon>({
            id: "frontpage-seed-beacons",
            data: seedBeacons,
            pickable: false,
            getPosition: (beacon) => [beacon.x, beacon.y],
            getRadius: (beacon) => 12 + Math.min(beacon.node_count, 14) * 1.1,
            getFillColor: () => withAlpha(runtime.theme.node, 92),
            getLineColor: () => withAlpha(runtime.theme.selected, 195),
            getLineWidth: () => 2,
            stroked: true,
            radiusUnits: "pixels",
            lineWidthUnits: "pixels",
          }),
        ]
      : []),
    new LineLayer<GraphEdge>({
      id: "frontpage-edges-base",
      data: baseEdges,
      getSourcePosition: (edge) => edge.source,
      getTargetPosition: (edge) => edge.target,
      getColor: (edge) =>
        edgeColor(edge, runtime.indexes, focusSets, focusState, runtime.theme, mode),
      getWidth: (edge) => edgeWidth(edge, focusSets, mode),
      widthUnits: "pixels",
      updateTriggers: {
        getColor: [
          runtime.activityNow,
          runtime.viewState.zoom,
          focusState.selected_node_id,
          focusState.selected_agent_id,
          focusState.subtree_root_id,
          focusState.subtree_mode,
          focusState.show_null_results,
          focusState.filter_to_null_results,
        ],
        getWidth: [
          runtime.viewState.zoom,
          focusState.selected_node_id,
          focusState.selected_agent_id,
          focusState.subtree_root_id,
          focusState.subtree_mode,
        ],
      },
    }),
    new LineLayer<ActivityTrace>({
      id: "frontpage-activity-traces",
      data: activityData.traces,
      pickable: false,
      getSourcePosition: (trace) => trace.source,
      getTargetPosition: (trace) => trace.target,
      getColor: (trace) => trace.color,
      getWidth: (trace) => trace.width,
      widthUnits: "pixels",
    }),
    new ScatterplotLayer<ActivityPulse>({
      id: "frontpage-status-pulses",
      data: statusPulses,
      pickable: false,
      getPosition: (pulse) => pulse.position,
      getRadius: (pulse) => pulse.radius,
      getFillColor: (pulse) => pulse.fillColor,
      filled: true,
      stroked: false,
      radiusUnits: "pixels",
    }),
    new ScatterplotLayer<ActivityPulse>({
      id: "frontpage-activity-glows",
      data: activityData.glows,
      pickable: false,
      getPosition: (pulse) => pulse.position,
      getRadius: (pulse) => pulse.radius,
      getFillColor: (pulse) => pulse.fillColor,
      filled: true,
      stroked: false,
      radiusUnits: "pixels",
    }),
    new ScatterplotLayer<ActivityPulse>({
      id: "frontpage-activity-rings",
      data: [...activityData.rings, ...statusPulses.filter((pulse) => pulse.lineWidth > 0)],
      pickable: false,
      getPosition: (pulse) => pulse.position,
      getRadius: (pulse) => pulse.radius,
      getLineColor: (pulse) => pulse.lineColor,
      getLineWidth: (pulse) => pulse.lineWidth,
      stroked: true,
      filled: false,
      radiusUnits: "pixels",
      lineWidthUnits: "pixels",
    }),
    new ScatterplotLayer<GraphNode>({
      id: "frontpage-nodes-base",
      data: baseNodes,
      pickable: true,
      autoHighlight: mode !== "watch",
      highlightColor: withAlpha(runtime.theme.hover, 110),
      getPosition: (node) => [node.x, node.y],
      getRadius: (node) => nodeImportance(node),
      getFillColor: (node) =>
        nodeFillColor(node, focusSets, focusState, runtime.theme, mode, runtime.activityNow),
      getLineColor: (node) => nodeLineColor(node, focusSets, runtime.theme, mode),
      getLineWidth: (node) =>
        focusSets.selectedNodeId === node.id
          ? 3.2
          : focusSets.lineageNodeIds.has(node.id)
            ? 2.6
            : focusSets.subtreeNodeIds.has(node.id) || focusSets.agentNodeIds.has(node.id)
              ? 2
              : 1,
      stroked: true,
      radiusUnits: "pixels",
      lineWidthUnits: "pixels",
      onHover: (info) =>
        handleNodeHover(
          runtime,
          (info.object as GraphNode | undefined) ?? null,
          info,
        ),
      onClick: (info) => {
        if (!info.object) return;

        const node = info.object as GraphNode;
        runtime.focusState = {
          ...runtime.focusState,
          selected_node_id: node.id,
        };
        renderGraph(runtime);
        animate(runtime.host, {
          scale: [0.996, 1],
          duration: 180,
          ease: "outCubic",
        });
        runtime.pushEvent("select-node", { node_id: node.id });
      },
      updateTriggers: {
        getRadius: [
          runtime.viewState.zoom,
          focusState.selected_node_id,
          focusState.selected_agent_id,
          focusState.subtree_root_id,
          focusState.subtree_mode,
        ],
        getFillColor: [
          runtime.activityNow,
          runtime.viewState.zoom,
          focusState.selected_node_id,
          focusState.selected_agent_id,
          focusState.subtree_root_id,
          focusState.subtree_mode,
          focusState.show_null_results,
          focusState.filter_to_null_results,
        ],
        getLineColor: [
          runtime.viewState.zoom,
          focusState.selected_node_id,
          focusState.selected_agent_id,
          focusState.subtree_root_id,
          focusState.subtree_mode,
        ],
      },
    }),
  ];
}

function handleNodeHover(
  runtime: GraphRuntime,
  node: GraphNode | null,
  info: PickingInfo<GraphNode>,
) {
  runtime.hoveredNodeId = node?.id ?? null;
  runtime.deck.setProps({
    getCursor: () => (node ? "pointer" : runtime.active ? "grab" : "default"),
  });
  setTooltip(runtime, node, info);
}

function renderGraph(runtime: GraphRuntime) {
  runtime.activityEvents = pruneActivityEvents(runtime.activityEvents, runtime.activityNow);
  runtime.chrome = lookupChrome(runtime.host);
  renderPalette(runtime);

  runtime.deck.setProps({
    layers: buildLayers(runtime),
    controller: graphController(runtime.active) as any,
    onClick: (info) => {
      if (!info.object) {
        runtime.pushEvent("clear-graph-focus", {});
      }
    },
    viewState: runtime.viewState as any,
  });
}

function updatePayload(runtime: GraphRuntime, nextPayload: GraphPayload) {
  pauseMotion(runtime.motion);

  const now = Date.now();
  const current = currentPositions(runtime);

  const previousPayload = runtime.payload;
  const activityAffordance = graphAffordances().activity;

  if (activityAffordance) {
    runtime.activityEvents = activityAffordance.diffActivityEvents({
      previousNodes: previousPayload.nodes,
      nextNodes: nextPayload.nodes,
      nextRevision: nextPayload.meta.revision,
      existingEvents: runtime.activityEvents,
      now,
    });
  } else {
    runtime.pendingActivityDiff = {
      previousPayload,
      nextPayload,
      now,
    };
    loadActivityAffordance(runtime);
  }

  runtime.sourcePositions = current;
  runtime.targetPositions = new Map(
    nextPayload.nodes.map((node) => [node.id, { x: node.x, y: node.y }]),
  );
  runtime.payload = nextPayload;
  runtime.indexes = buildIndexes(nextPayload);
  runtime.searchIndex = buildSearchIndex(nextPayload, runtime.indexes);
  runtime.transition.progress = 0;

  runtime.motion = animate(runtime.transition, {
    progress: 1,
    duration: 560,
    ease: "outCubic",
    onUpdate: () => renderGraph(runtime),
    onComplete: () => {
      runtime.motion = null;
    },
  }) as AnimationHandle;
}

function createRuntime(hook: GraphHook): GraphRuntime | null {
  const host = hook.el as HTMLElement;
  const deckRoot = host.querySelector<HTMLDivElement>("[data-deck-root]");
  const tooltip = host.querySelector<HTMLDivElement>("[data-graph-tooltip]");

  if (!deckRoot) return null;
  const labelRoot = ensureLabelRoot(host);

  const payload = parseJson<GraphPayload>(host.dataset.graph, defaultPayload);
  const focusState = mergeFocusState(host, parseJson<FocusState>(host.dataset.focus, defaultFocus));
  const theme = resolveGraphTheme(host);
  const viewState = fitViewStateForPayload(payload, deckRoot);

  const deck = new Deck({
    parent: deckRoot,
    width: "100%",
    height: "100%",
    views: [new OrthographicView({ id: "frontpage-orthographic" })],
    controller: graphController(readBool(host.dataset.active)) as any,
    initialViewState: viewState as any,
    getCursor: () => (readBool(host.dataset.active) ? "grab" : "default"),
    onViewStateChange: ({ viewState: nextViewState }) => {
      viewState.target = [
        ...((nextViewState.target as [number, number, number] | undefined) ?? [0, 0, 0]),
      ] as [number, number, number];
      viewState.zoom = typeof nextViewState.zoom === "number" ? nextViewState.zoom : 0;
      renderGraph(runtime);
      return nextViewState;
    },
  });

  const runtime: GraphRuntime = {
    host,
    deckRoot,
    labelRoot,
    tooltip,
    deck,
    pushEvent: hook.pushEvent.bind(hook),
    payload,
    indexes: buildIndexes(payload),
    focusState,
    active: readBool(host.dataset.active),
    theme,
    themeObserver: new MutationObserver(() => {
      runtime.theme = resolveGraphTheme(host);
      renderGraph(runtime);
    }),
    resizeObserver: new ResizeObserver(() => {
      renderGraph(runtime);
    }),
    transition: { progress: 1 },
    motion: null,
    viewMotion: null,
    sourcePositions: new Map(payload.nodes.map((node) => [node.id, { x: node.x, y: node.y }])),
    targetPositions: new Map(payload.nodes.map((node) => [node.id, { x: node.x, y: node.y }])),
    viewState,
    chrome: lookupChrome(host),
    hoveredNodeId: null,
    activityEvents: [],
    activityNow: Date.now(),
    tickTimer: null,
    activityAffordanceLoading: null,
    labelsAffordanceLoading: null,
    pendingActivityDiff: null,
    searchIndex: buildSearchIndex(payload, buildIndexes(payload)),
    paletteOpen: false,
    paletteQuery: "",
    paletteSelectedIndex: 0,
    onHostClick: (event) => {
      const target = event.target as HTMLElement | null;
      if (!target) return;

      const cameraAction = target.closest<HTMLElement>("[data-graph-camera-action]");
      if (cameraAction) {
        event.preventDefault();
        event.stopPropagation();

        switch (cameraAction.dataset.graphCameraAction) {
          case "zoom-in":
            zoomGraphView(runtime, 0.5);
            break;
          case "zoom-out":
            zoomGraphView(runtime, -0.5);
            break;
          default:
            fitGraphView(runtime, { animate: true });
            break;
        }

        renderGraph(runtime);
        return;
      }

      const paletteAction = target.closest<HTMLElement>("[data-graph-palette-action]");
      if (paletteAction) {
        event.preventDefault();
        event.stopPropagation();

        switch (paletteAction.dataset.graphPaletteAction) {
          case "open":
            openPalette(runtime);
            break;
          case "close":
            closePalette(runtime);
            break;
          case "result": {
            const results = currentPaletteResults(runtime);
            const index = Number.parseInt(paletteAction.dataset.graphPaletteResultIndex || "0", 10);
            const match = results[index];
            if (match) {
              runtime.paletteSelectedIndex = index;
              selectSearchMatch(runtime, match, true);
            }
            break;
          }
        }

        return;
      }
    },
    onHostInput: (event) => {
      const input = event.target as HTMLInputElement | null;
      if (!input || input !== runtime.chrome.paletteInput) return;
      runtime.paletteQuery = input.value;
      runtime.paletteSelectedIndex = 0;
      renderPalette(runtime);
    },
    onWindowKeyDown: (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        if (runtime.paletteOpen) {
          closePalette(runtime);
        } else {
          openPalette(runtime);
        }
        return;
      }

      if (!runtime.paletteOpen) return;

      if (event.key === "Escape") {
        event.preventDefault();
        closePalette(runtime);
        return;
      }

      const results = currentPaletteResults(runtime);
      if (results.length === 0) return;

      if (event.key === "ArrowDown") {
        event.preventDefault();
        runtime.paletteSelectedIndex = clamp(runtime.paletteSelectedIndex + 1, 0, results.length - 1);
        renderPalette(runtime);
        return;
      }

      if (event.key === "ArrowUp") {
        event.preventDefault();
        runtime.paletteSelectedIndex = clamp(runtime.paletteSelectedIndex - 1, 0, results.length - 1);
        renderPalette(runtime);
        return;
      }

      if (event.key === "Enter") {
        event.preventDefault();
        const match = results[runtime.paletteSelectedIndex] ?? results[0];
        if (match) {
          selectSearchMatch(runtime, match, !event.shiftKey);
        }
      }
    },
  };

  deckRoot.style.touchAction = "none";
  host.addEventListener("click", runtime.onHostClick);
  host.addEventListener("input", runtime.onHostInput);
  window.addEventListener("keydown", runtime.onWindowKeyDown);

  runtime.themeObserver.observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["data-theme"],
  });
  runtime.resizeObserver.observe(deckRoot);

  hook.handleEvent("frontpage:graph-focus", (payloadValue: unknown) => {
    runtime.focusState = mergeFocusState(host, payloadValue as FocusState);
    renderGraph(runtime);
  });

  runtime.tickTimer = window.setInterval(() => {
    runtime.activityNow = Date.now();
    if (runtime.active || runtime.activityEvents.length > 0) {
      renderGraph(runtime);
    }
  }, GRAPH_TICK_MS);

  animate(deckRoot, {
    opacity: [0, 1],
    scale: [0.985, 1],
    duration: 420,
    ease: "outCubic",
  });

  fitGraphView(runtime, { animate: true });
  renderGraph(runtime);
  return runtime;
}

export const FrontpageGraph: Hook = {
  mounted() {
    const hook = this as GraphHook;
    hook.__graph = createRuntime(hook) ?? undefined;
  },

  updated() {
    const hook = this as GraphHook;
    const runtime = hook.__graph;

    if (!runtime) return;

    const host = this.el as HTMLElement;
    const nextPayload = parseJson<GraphPayload>(host.dataset.graph, defaultPayload);
    const nextFocus = mergeFocusState(host, parseJson<FocusState>(host.dataset.focus, defaultFocus));
    const nextActive = readBool(host.dataset.active);

    runtime.chrome = lookupChrome(host);
    runtime.active = nextActive;
    runtime.focusState = nextFocus;

    if (nextPayload.meta.revision !== runtime.payload.meta.revision) {
      updatePayload(runtime, nextPayload);
      renderGraph(runtime);
      return;
    }

    renderGraph(runtime);
  },

  destroyed() {
    const hook = this as GraphHook;
    const runtime = hook.__graph;

    if (!runtime) return;

    pauseMotion(runtime.motion);
    pauseMotion(runtime.viewMotion);
    if (runtime.tickTimer != null) {
      window.clearInterval(runtime.tickTimer);
    }
    runtime.labelRoot.replaceChildren();
    runtime.labelRoot.remove();
    runtime.themeObserver.disconnect();
    runtime.resizeObserver.disconnect();
    runtime.host.removeEventListener("click", runtime.onHostClick);
    runtime.host.removeEventListener("input", runtime.onHostInput);
    window.removeEventListener("keydown", runtime.onWindowKeyDown);
    runtime.deck.finalize();
    setTooltip(runtime, null, {} as PickingInfo<GraphNode>);
  },
};
