import {
  registerGraphAffordances,
  type GraphFocusSetsAffordance,
  type GraphFocusStateAffordance,
  type GraphLabelOverlayInput,
  type GraphNodeAffordance,
  type GraphViewportMode,
} from "./hooks/home-graph/affordances";

function nodeImportance(node: GraphNodeAffordance): number {
  const score = node.score ?? node.watcher_count ?? 0;
  return 6 + Math.min(score, 16) * 0.45 + Math.max(0, 3 - node.depth) * 1.2;
}

function nodeVisible(node: GraphNodeAffordance, focusState: GraphFocusStateAffordance): boolean {
  return !focusState.filter_to_null_results || node.result_status === "null";
}

function uniqueNodes(nodes: GraphNodeAffordance[]): GraphNodeAffordance[] {
  const seen = new Set<number>();
  return nodes.filter((node) => {
    if (seen.has(node.id)) return false;
    seen.add(node.id);
    return true;
  });
}

function labelNodes(
  nodes: GraphNodeAffordance[],
  focusSets: GraphFocusSetsAffordance,
  focusState: GraphFocusStateAffordance,
  mode: GraphViewportMode,
): GraphNodeAffordance[] {
  if (mode !== "inspect") return [];

  const visible = nodes.filter((node) => nodeVisible(node, focusState));
  const selected = visible.filter((node) => node.id === focusSets.selectedNodeId);
  const emphasized = visible.filter(
    (node) =>
      focusSets.lineageNodeIds.has(node.id) ||
      focusSets.subtreeNodeIds.has(node.id) ||
      focusSets.agentNodeIds.has(node.id) ||
      (focusState.show_null_results && focusSets.nullNodeIds.has(node.id)),
  );
  const ranked = [...visible].sort((left, right) => nodeImportance(right) - nodeImportance(left));

  return uniqueNodes([...selected, ...emphasized.slice(0, 14), ...ranked.slice(0, 22)]);
}

function projectPosition(
  node: GraphNodeAffordance,
  input: GraphLabelOverlayInput,
): { x: number; y: number } {
  const scale = 2 ** input.viewState.zoom;
  return {
    x: (node.x - input.viewState.target[0]) * scale + input.viewport.width / 2,
    y: (input.viewState.target[1] - node.y) * scale + input.viewport.height / 2,
  };
}

function visibleWithinViewport(
  position: { x: number; y: number },
  viewport: GraphLabelOverlayInput["viewport"],
): boolean {
  return (
    position.x >= -140 &&
    position.x <= viewport.width + 140 &&
    position.y >= -64 &&
    position.y <= viewport.height + 96
  );
}

function clearLabels(root: HTMLElement) {
  root.replaceChildren();
  root.dataset.visible = "false";
}

registerGraphAffordances({
  labels: {
    clearLabels,

    renderLabels(input: GraphLabelOverlayInput) {
      const labels = labelNodes(input.nodes, input.focusSets, input.focusState, input.mode);
      if (labels.length === 0) {
        clearLabels(input.root);
        return;
      }

      const fragment = document.createDocumentFragment();

      for (const node of labels) {
        const position = projectPosition(node, input);
        if (!visibleWithinViewport(position, input.viewport)) continue;

        const label = document.createElement("div");
        label.className =
          input.focusSets.selectedNodeId === node.id
            ? "fp-graph-node-label is-selected"
            : "fp-graph-node-label";
        label.textContent = node.label;
        label.style.transform = `translate3d(${Math.round(position.x)}px, ${Math.round(position.y)}px, 0)`;
        fragment.appendChild(label);
      }

      input.root.replaceChildren(fragment);
      input.root.dataset.visible = input.root.childElementCount > 0 ? "true" : "false";
    },
  },
});
