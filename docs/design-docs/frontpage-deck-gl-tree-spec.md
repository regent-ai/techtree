# Frontpage Deck.gl Tree Spec

## Status

Draft design spec for the homepage DAG renderer hard cutover.

## Scope

Replace the current custom WebGL homepage graph renderer with a deck.gl-backed renderer on the homepage route. Keep Phoenix LiveView as the canonical state owner and keep the existing TypeScript hook bridge pattern.

This spec applies to:

- [lib/tech_tree_web/live/frontpage_demo_live.ex](/Users/sean/Documents/regent/techtree/lib/tech_tree_web/live/frontpage_demo_live.ex)
- [assets/js/hooks/home-grid.ts](/Users/sean/Documents/regent/techtree/assets/js/hooks/home-grid.ts)
- [assets/js/hooks/home-windows.ts](/Users/sean/Documents/regent/techtree/assets/js/hooks/home-windows.ts)
- [assets/js/hooks/home-graph/index.ts](/Users/sean/Documents/regent/techtree/assets/js/hooks/home-graph/index.ts)
- [assets/js/hooks/index.ts](/Users/sean/Documents/regent/techtree/assets/js/hooks/index.ts)
- [assets/js/app.ts](/Users/sean/Documents/regent/techtree/assets/js/app.ts)

## Existing constraints

- LiveView already renders the homepage graph shell and passes graph data through `data-graph`, `data-selected-node-id`, `data-layout-mode`, and `data-active` on the `FrontpageGraph` hook host.
- The current hook already sends selection back to LiveView with `pushEvent("select-node", { node_id })`.
- The repo uses Phoenix `esbuild` as the browser bundler. This is not a separate SPA.
- The homepage already uses typed hooks and imperative browser islands. The deck.gl graph must follow that model.
- Hard cutover only. Do not keep the old raw WebGL renderer around behind a flag.

## Product goals

- Render the homepage node DAG with deck.gl in an orthographic Cartesian view.
- Highlight all nodes authored by a selected agent.
- Highlight all direct children or all descendants of a selected node.
- Highlight and optionally filter null-result nodes.
- Preserve smooth pan, zoom, picking, and tooltip behavior.
- Keep transient hover local to the client and keep pinned selection synchronized with LiveView.

## Non-goals

- No React wrapper.
- No geospatial map view.
- No force-directed layout.
- No backwards-compatible dual renderer.
- No client-owned source of truth for graph state.

## Rendering model

Use `Deck` with `OrthographicView` and `controller: true` in Cartesian coordinates.

The renderer is split into three parts:

1. `layout engine`
   Produces stable `[x, y]` positions for each node outside deck.gl.
2. `graph state engine`
   Produces descendants, nodes-by-agent, null-result sets, and edge indexes outside deck.gl.
3. `deck.gl renderer`
   Draws nodes, edges, icons, and labels from those precomputed structures.

The deck.gl layer stack is the implementation surface, not the layout engine.

## Hard cutover architecture

Keep `phx-hook="FrontpageGraph"` on the homepage graph shell. Replace the internals of that hook with a deck.gl runtime.

Target DOM structure inside [lib/tech_tree_web/live/home_live.ex](/Users/sean/Documents/regent/techtree/lib/tech_tree_web/live/home_live.ex):

```heex
<section
  id="frontpage-home-graph"
  phx-hook="FrontpageGraph"
  data-graph={@graph_payload_json}
  data-focus={@graph_focus_json}
  data-selected-node-id={to_string(@selected_node_id || "")}
  data-active={to_string(@view_mode == "graph")}
>
  <div class="fp-deck-root" data-deck-root="" phx-update="ignore"></div>
  <div class="fp-graph-tooltip" data-graph-tooltip=""></div>
</section>
```

Rules:

- The deck canvas lives under a single ignored root so deck.gl owns its DOM subtree.
- The outer LiveView section remains patchable so assigns, mode toggles, and test selectors stay stable.
- The public hook name stays `FrontpageGraph` to avoid unnecessary template churn.

## Asset pipeline

Keep Phoenix `esbuild` as the bundler. Introduce browser dependencies for deck.gl in `assets/` and bundle them through the existing `js/app.ts` entrypoint.

Required packages:

- `@deck.gl/core`
- `@deck.gl/layers`
- `@deck.gl/extensions`

Optional later:

- `@deck.gl/geo-layers` only if `TileLayer` is needed for very large trees

The browser dependency install method is an implementation detail. The required outcome is that `esbuild tech_tree` resolves deck.gl from the existing Phoenix asset build without introducing a second frontend runtime.

## Data contract

Deck receives render-ready graph data. The renderer does not infer semantic state from presentation-only fields.

```ts
type NodeStatus = "success" | "null" | "failed" | "pending";

type TechTreeNode = {
  id: string;
  label: string;
  x: number;
  y: number;
  z?: number;
  depth: number;
  parentIds: string[];
  childIds: string[];
  agentId: string | null;
  agentLabel: string | null;
  resultStatus: NodeStatus;
  score?: number;
  stake?: number;
  commentCount?: number;
  createdAt?: number;
  isComment?: boolean;
  kind: string;
  seed: string;
  summary?: string | null;
};

type TechTreeEdge = {
  id: string;
  sourceId: string;
  targetId: string;
  source: [number, number, number?];
  target: [number, number, number?];
  kind: "tree" | "citation" | "comment" | "derived";
};

type GraphIndexes = {
  nodeById: Map<string, TechTreeNode>;
  childrenById: Map<string, string[]>;
  descendantsById: Map<string, string[]>;
  nodesByAgentId: Map<string, string[]>;
  nullResultNodeIds: Set<string>;
  edgeIdsByNodeId: Map<string, string[]>;
};

type FocusState = {
  hoveredNodeId?: string;
  selectedNodeId?: string;
  selectedAgentId?: string;
  subtreeRootId?: string;
  subtreeMode?: "children" | "descendants";
  showNullResults?: boolean;
  filterToNullResults?: boolean;
};

type TechTreeGraphPayload = {
  nodes: TechTreeNode[];
  edges: TechTreeEdge[];
  focus: FocusState;
  meta: {
    revision: number;
    layoutMode: string;
  };
};
```

### Required payload changes from current homepage graph

The current `GraphNode` payload in [assets/js/hooks/home-grid.ts](/Users/sean/Documents/regent/techtree/assets/js/hooks/home-grid.ts) is insufficient for the target feature set. The homepage payload must gain:

- `x` and `y` positions
- `parentIds` and `childIds`
- explicit `edges`
- `agentId` and `agentLabel`
- `resultStatus`
- a `focus` packet
- a monotonic `meta.revision`

`parent_id` alone is not enough once the homepage is treated as a DAG rather than a strict tree.

## Indexes and layout ownership

Deck.gl only renders. It does not compute graph topology or hierarchy.

Rules:

- Layout positions are computed before layer creation.
- Descendant sets are computed before layer creation.
- `nodesByAgentId` is computed before layer creation.
- These derived indexes are memoized by `meta.revision`.

The initial implementation may compute indexes in the hook. The renderer-facing contract remains the same: deck layers consume stable arrays plus derived lookup structures.

## Layer stack

Render layers in this order:

1. `edges-base`
   `LineLayer` for parent-to-child tree edges.
2. `edges-secondary`
   `LineLayer` for citation, comment, and derived edges.
3. `edges-focus`
   `LineLayer` for subtree and agent focus overlays.
4. `nodes-base`
   `ScatterplotLayer` for all nodes.
5. `nodes-null-icons`
   `IconLayer` for null-result markers.
6. `nodes-focus`
   `ScatterplotLayer` for selected node, subtree, and agent halos.
7. `labels-base`
   `TextLayer` for visible labels.
8. `labels-focus`
   `TextLayer` for selected and high-priority labels.

## Composite layer

Wrap the renderer in a custom `TechTreeLayer extends CompositeLayer`.

Public props:

```ts
type TechTreeLayerProps = {
  nodes: TechTreeNode[];
  edges: TechTreeEdge[];
  indexes: GraphIndexes;
  focusState: FocusState;
  showLabels?: boolean;
  showSecondaryEdges?: boolean;
  showComments?: boolean;
  labelMode?: "none" | "selected" | "top" | "all-visible";
  nodeRadiusScale?: number;
  edgeWidthScale?: number;
  onNodeHover?: (node: TechTreeNode | null) => void;
  onNodeClick?: (node: TechTreeNode) => void;
  onEdgeClick?: (edge: TechTreeEdge) => void;
};
```

`TechTreeLayer` must expose graph-native events to the hook and hide sublayer details from the rest of the app.

## Visual encoding

Base node encoding:

- position: precomputed `[x, y]`
- radius: score, stake, or watcher-derived importance
- fill color: result status or node kind
- stroke: subtle baseline stroke
- opacity: medium by default

Base edge encoding:

- tree edges: thin, low-opacity
- secondary edges: lighter than tree edges
- focus edges: thicker and brighter

Null-result nodes:

- keep them in the base node layer for spatial continuity
- add a dedicated icon or ring in `nodes-null-icons`
- do not rely on color alone

Agent-authored nodes:

- brighten matching nodes
- dim non-matching nodes
- optionally add a halo overlay
- optionally brighten incident edges

Selected subtree:

- selected root gets the strongest halo
- children or descendants get a medium halo
- subtree edges are brightened and thickened

## Highlight and filter modes

Highlight means keep everything visible but emphasize a subset.

Filter means hide or heavily fade non-matching objects.

Use both.

Rules:

- Hover uses deck.gl picking and stays local to the client.
- Multi-object highlights do not use `autoHighlight` alone.
- Agent focus, subtree focus, and null-result focus are driven by `FocusState`.
- Small enum filters such as `resultStatus` may use `DataFilterExtension`.
- Large agent-cardinality focus must use overlay layers and accessor styling, not category filtering.

## Highlight priority

Priority order:

1. selected node
2. subtree descendants or children
3. selected agent
4. null-result
5. hover
6. base state

This priority order is deterministic and must be shared by node, edge, and label styling functions.

## Labels

Do not label everything at every zoom level.

Default behavior:

- low zoom: selected label only
- medium zoom: selected, hovered, and top-ranked visible labels
- high zoom: many visible labels with collision filtering

Use `TextLayer` with `CollisionFilterExtension`.

Rules:

- all label layers share one collision group
- use a fixed character set when possible
- selected labels bypass most fading

## Interaction contract

Client-local interactions:

- hover tooltip
- hover highlight
- pan and zoom
- label collision

LiveView-synchronized interactions:

- click node to select
- set selected agent
- toggle null-result highlight or filter
- set subtree mode to `children` or `descendants`
- clear pinned focus

Event contract from hook to LiveView:

```ts
type GraphClientEvent =
  | { type: "select-node"; nodeId: string }
  | { type: "focus-agent"; agentId: string | null }
  | { type: "focus-subtree"; nodeId: string; mode: "children" | "descendants" }
  | { type: "toggle-null-results"; enabled: boolean }
  | { type: "filter-null-results"; enabled: boolean }
  | { type: "clear-focus" };
```

Phoenix event names:

- `select-node`
- `focus-agent`
- `focus-subtree`
- `toggle-null-results`
- `filter-null-results`
- `clear-graph-focus`

Server-to-client update paths:

1. low-frequency topology changes
   LiveView updates `data-graph` and `data-focus`
2. focus-only changes
   LiveView may use `push_event("frontpage:graph-focus", packet)` and the hook handles it with `handleEvent`

Use the second path for cheap style-only updates so deck layers can update accessors without replacing node or edge arrays.

## Hook design

Keep the existing hook names, but split the implementation into smaller TypeScript modules instead of growing [assets/js/hooks/home-grid.ts](/Users/sean/Documents/regent/techtree/assets/js/hooks/home-grid.ts) and [assets/js/hooks/home-graph/index.ts](/Users/sean/Documents/regent/techtree/assets/js/hooks/home-graph/index.ts) further.

Recommended modules:

- `assets/js/hooks/frontpage-graph/types.ts`
- `assets/js/hooks/frontpage-graph/indexes.ts`
- `assets/js/hooks/frontpage-graph/layer.ts`
- `assets/js/hooks/frontpage-graph/theme.ts`
- `assets/js/hooks/frontpage-graph/runtime.ts`

The exported `FrontpageGraph` hook remains registered through [assets/js/hooks/index.ts](/Users/sean/Documents/regent/techtree/assets/js/hooks/index.ts).

Hook behavior:

- mount a single `Deck` instance once
- rebuild layout and indexes only when `meta.revision` changes
- update focus and theme through `setProps`
- forward deck picking events to `pushEvent`
- destroy the `Deck` instance on `destroyed`

## LiveView ownership

LiveView remains the canonical owner of:

- selected node
- selected agent
- subtree mode
- null-result filter state
- current data mode
- detail panels and chatbox content derived from the selected node

The hook owns:

- deck instance lifecycle
- local hover state
- current viewport
- tooltip position
- zoom-dependent label density

Do not mirror the full graph state into a parallel client store.

## Performance rules

- Keep `nodes` and `edges` arrays stable between focus-only updates.
- Memoize indexes by `meta.revision`.
- Use `updateTriggers` for accessor changes driven by `FocusState`.
- Replace data arrays only when graph topology or layout changes.
- Prefer overlay layers for high-cardinality focus.
- Reserve `TileLayer` for future very large graphs.

Example accessor triggers:

```ts
updateTriggers: {
  getFillColor: [
    focusState.selectedNodeId,
    focusState.selectedAgentId,
    focusState.showNullResults,
    focusState.filterToNullResults,
  ],
  getRadius: [focusState.selectedNodeId, focusState.selectedAgentId],
  getLineColor: [
    focusState.selectedNodeId,
    focusState.selectedAgentId,
    focusState.subtreeRootId,
    focusState.subtreeMode,
  ],
}
```

## Theming

Continue sourcing colors from the homepage CSS custom properties already attached to the outer LiveView shell.

The deck runtime reads the same theme token family currently used by the raw WebGL graph:

- `--fp-graph-edge`
- `--fp-graph-node`
- `--fp-graph-node-alt`
- `--fp-graph-hover`
- `--fp-graph-selected`
- `--fp-graph-background`

Add new tokens only for new semantics that do not fit the existing set, such as null-result halo or agent-focus border.

## Accessibility

- Keep keyboard-accessible controls for agent focus and null-result toggles in LiveView markup.
- Mirror pinned selection into non-canvas detail UI so there is always a semantic text surface.
- Do not make hover the only way to discover node identity.
- Ensure non-color cues for null-result state.

## Phased delivery

### Phase 1

- Replace the current graph renderer with deck.gl
- Preserve current click-to-select behavior
- Preserve tooltip and theme support

### Phase 2

- Add `TechTreeLayer`
- Add subtree highlighting for children and descendants
- Add null-result overlay

### Phase 3

- Add agent-wide highlighting
- Add focus push events for style-only updates
- Add collision-managed labels

### Phase 4

- Add optional large-graph tiling if the homepage payload grows beyond a single practical deck scene

## Validation

For implementation against this spec:

- `mix precommit`
- `bash qa/phase-c-smoke.sh` or the relevant homepage harness

For this doc-only change, run:

- the relevant doc review pass
