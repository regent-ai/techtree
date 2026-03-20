import {
  registerGraphAffordances,
  type GraphActivityDiffInput,
  type GraphActivityEvent,
  type GraphActivityInput,
  type GraphActivityIntensity,
  type GraphNodeAffordance,
  type GraphStatusPulseInput,
} from "./hooks/home-graph/affordances";

const GRAPH_ACTIVITY_TTL_MS = 12_000;

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

function withAlpha(
  color: [number, number, number],
  alpha: number,
): [number, number, number, number] {
  return [color[0], color[1], color[2], clamp(alpha, 0, 255)];
}

function nodeImportance(node: GraphNodeAffordance): number {
  const score = node.score ?? node.watcher_count ?? 0;
  return 6 + Math.min(score, 16) * 0.45 + Math.max(0, 3 - node.depth) * 1.2;
}

function nodeVisible(node: GraphNodeAffordance, focusState: GraphStatusPulseInput["focusState"]): boolean {
  return !focusState.filter_to_null_results || node.result_status === "null";
}

function statusPhase(node: GraphNodeAffordance, now: number): number {
  return (now / 900 + node.id * 0.13) % (Math.PI * 2);
}

function intensityForDelta(delta: number): GraphActivityIntensity {
  if (delta >= 4) return "high";
  if (delta >= 2) return "medium";
  return "low";
}

function eventIntensityScale(intensity: GraphActivityIntensity): number {
  switch (intensity) {
    case "high":
      return 1.25;
    case "medium":
      return 1;
    default:
      return 0.8;
  }
}

function pruneActivityEvents(events: GraphActivityEvent[], now: number): GraphActivityEvent[] {
  return events.filter((event) => now - event.occurred_at <= GRAPH_ACTIVITY_TTL_MS);
}

registerGraphAffordances({
  activity: {
    diffActivityEvents<TNode extends GraphNodeAffordance>({
      previousNodes,
      nextNodes,
      nextRevision,
      existingEvents,
      now,
    }: GraphActivityDiffInput<TNode>) {
      const previousById = new Map(previousNodes.map((node) => [node.id, node]));
      const pruned = pruneActivityEvents(existingEvents, now);
      const knownEventIds = new Set(pruned.map((event) => event.id));
      const nextEvents = [...pruned];

      for (const node of nextNodes) {
        const previousNode = previousById.get(node.id);

        if (!previousNode) {
          const eventId = `node_created:${nextRevision}:${node.id}`;
          if (!knownEventIds.has(eventId)) {
            nextEvents.push({
              id: eventId,
              kind: "node_created",
              node_id: node.id,
              parent_node_id: (node as TNode & { parent_id?: number | null }).parent_id ?? null,
              occurred_at: now,
              intensity: "high",
            });
            knownEventIds.add(eventId);
          }
          continue;
        }

        const nextCommentCount = (node as TNode & { comment_count?: number }).comment_count || 0;
        const previousCommentCount =
          (previousNode as TNode & { comment_count?: number }).comment_count || 0;
        const commentDelta = nextCommentCount - previousCommentCount;
        if (commentDelta > 0) {
          const eventId = `comment_added:${nextRevision}:${node.id}`;
          if (!knownEventIds.has(eventId)) {
            nextEvents.push({
              id: eventId,
              kind: "comment_added",
              node_id: node.id,
              parent_node_id: (node as TNode & { parent_id?: number | null }).parent_id ?? null,
              occurred_at: now,
              intensity: intensityForDelta(commentDelta),
            });
            knownEventIds.add(eventId);
          }
        }

        const watcherDelta = (node.watcher_count || 0) - (previousNode.watcher_count || 0);
        if (watcherDelta > 0) {
          const eventId = `watch_added:${nextRevision}:${node.id}`;
          if (!knownEventIds.has(eventId)) {
            nextEvents.push({
              id: eventId,
              kind: "watch_added",
              node_id: node.id,
              parent_node_id: (node as TNode & { parent_id?: number | null }).parent_id ?? null,
              occurred_at: now,
              intensity: intensityForDelta(watcherDelta),
            });
            knownEventIds.add(eventId);
          }
        }
      }

      return nextEvents;
    },

    deriveActivityLayerData({ events, indexes, positions, theme, now }: GraphActivityInput) {
      const traces = [];
      const glows = [];
      const rings = [];

      for (const event of events) {
        const position = positions.get(event.node_id);
        if (!position) continue;

        const age = now - event.occurred_at;
        const progress = clamp(age / GRAPH_ACTIVITY_TTL_MS, 0, 1);
        const remaining = 1 - progress;
        const scale = eventIntensityScale(event.intensity);
        const glowColor =
          event.kind === "watch_added"
            ? withAlpha(theme.node, 180 * remaining)
            : event.kind === "comment_added"
              ? withAlpha(theme.hover, 190 * remaining)
              : event.kind === "payment_placeholder"
                ? withAlpha(theme.selected, 220 * remaining)
                : withAlpha(theme.selected, 235 * remaining);

        glows.push({
          id: `${event.id}:glow`,
          position: [position.x, position.y] as [number, number],
          radius: 14 * scale + progress * 22 * scale,
          fillColor: glowColor,
          lineColor: glowColor,
          lineWidth: 0,
        });

        rings.push({
          id: `${event.id}:ring`,
          position: [position.x, position.y] as [number, number],
          radius:
            event.kind === "watch_added"
              ? 10 * scale + progress * 18 * scale
              : 12 * scale + progress * 34 * scale,
          fillColor: withAlpha(theme.hover, 0),
          lineColor:
            event.kind === "comment_added"
              ? withAlpha(theme.hover, 210 * remaining)
              : event.kind === "payment_placeholder"
                ? withAlpha(theme.selected, 220 * remaining)
                : withAlpha(theme.selected, 180 * remaining),
          lineWidth: event.kind === "watch_added" ? 1.5 : 2.5,
        });

        if (event.kind === "node_created") {
          const parentId = event.parent_node_id ?? indexes.parentById.get(event.node_id) ?? null;
          const parentPosition = parentId != null ? positions.get(parentId) : null;

          if (parentPosition) {
            traces.push({
              id: `${event.id}:trace`,
              source: [parentPosition.x, parentPosition.y] as [number, number],
              target: [position.x, position.y] as [number, number],
              color: withAlpha(theme.selected, 235 * remaining),
              width: 5 * remaining * scale + 1.2,
            });
          }
        }
      }

      return { traces, glows, rings };
    },

    deriveStatusPulseNodes({ nodes, focusState, mode, now, theme }: GraphStatusPulseInput) {
      if (mode === "watch") return [];

      return nodes
        .filter((node) => nodeVisible(node, focusState))
        .flatMap((node) => {
          if (node.result_status === "success") return [];

          const phase = Math.sin(statusPhase(node, now));
          const radius = nodeImportance(node) + 6 + Math.max(0, phase * 6);

          if (node.result_status === "null") {
            return [
              {
                id: `status:null:${node.id}`,
                position: [node.x, node.y] as [number, number],
                radius,
                fillColor: withAlpha(theme.selected, 0),
                lineColor: withAlpha(theme.selected, 130 + phase * 40),
                lineWidth: 1.6 + Math.max(0, phase * 0.9),
              },
            ];
          }

          if (node.result_status === "failed") {
            return [
              {
                id: `status:failed:${node.id}`,
                position: [node.x, node.y] as [number, number],
                radius,
                fillColor: [149, 44, 44, 58 + Math.max(0, phase) * 48],
                lineColor: [149, 44, 44, 0],
                lineWidth: 0,
              },
            ];
          }

          return [
            {
              id: `status:pending:${node.id}`,
              position: [node.x, node.y] as [number, number],
              radius,
              fillColor: withAlpha(theme.nodeAlt, 42 + Math.max(0, phase) * 36),
              lineColor: withAlpha(theme.nodeAlt, 0),
              lineWidth: 0,
            },
          ];
        });
    },
  },
});
