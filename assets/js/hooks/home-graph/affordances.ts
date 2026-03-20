export type GraphViewportMode = "watch" | "navigate" | "inspect";
export type GraphActivityKind =
  | "node_created"
  | "comment_added"
  | "watch_added"
  | "payment_placeholder";
export type GraphActivityIntensity = "low" | "medium" | "high";

export type GraphNodeAffordance = {
  id: number;
  label: string;
  x: number;
  y: number;
  depth: number;
  result_status: "success" | "null" | "failed" | "pending";
  score?: number;
  watcher_count: number;
};

export type GraphFocusStateAffordance = {
  show_null_results?: boolean;
  filter_to_null_results?: boolean;
};

export type GraphFocusSetsAffordance = {
  selectedNodeId: number | null;
  lineageNodeIds: Set<number>;
  agentNodeIds: Set<number>;
  subtreeNodeIds: Set<number>;
  nullNodeIds: Set<number>;
};

export type GraphThemeAffordance = {
  hover: [number, number, number];
  selected: [number, number, number];
  background: [number, number, number];
  node: [number, number, number];
  nodeAlt: [number, number, number];
};

export type GraphIndexesAffordance = {
  parentById: Map<number, number | null>;
};

export type GraphActivityEvent = {
  id: string;
  kind: GraphActivityKind;
  node_id: number;
  parent_node_id?: number | null;
  amount?: number | null;
  occurred_at: number;
  intensity: GraphActivityIntensity;
};

export type ActivityTrace = {
  id: string;
  source: [number, number];
  target: [number, number];
  color: [number, number, number, number];
  width: number;
};

export type ActivityPulse = {
  id: string;
  position: [number, number];
  radius: number;
  fillColor: [number, number, number, number];
  lineColor: [number, number, number, number];
  lineWidth: number;
};

export type GraphActivityLayerData = {
  traces: ActivityTrace[];
  glows: ActivityPulse[];
  rings: ActivityPulse[];
};

export type GraphLabelOverlayInput = {
  nodes: GraphNodeAffordance[];
  focusSets: GraphFocusSetsAffordance;
  focusState: GraphFocusStateAffordance;
  mode: GraphViewportMode;
  theme: GraphThemeAffordance;
  root: HTMLElement;
  viewState: {
    target: [number, number, number];
    zoom: number;
  };
  viewport: {
    width: number;
    height: number;
  };
};

export type GraphActivityInput = {
  events: GraphActivityEvent[];
  indexes: GraphIndexesAffordance;
  positions: Map<number, { x: number; y: number }>;
  theme: GraphThemeAffordance;
  now: number;
};

export type GraphStatusPulseInput = {
  nodes: GraphNodeAffordance[];
  focusState: GraphFocusStateAffordance;
  mode: GraphViewportMode;
  now: number;
  theme: GraphThemeAffordance;
};

export type GraphActivityDiffInput<TNode extends GraphNodeAffordance> = {
  previousNodes: TNode[];
  nextNodes: TNode[];
  nextRevision: number;
  existingEvents: GraphActivityEvent[];
  now: number;
};

export type GraphLabelAffordance = {
  renderLabels: (input: GraphLabelOverlayInput) => void;
  clearLabels: (root: HTMLElement) => void;
};

export type GraphActivityAffordance = {
  diffActivityEvents: <TNode extends GraphNodeAffordance>(
    input: GraphActivityDiffInput<TNode>,
  ) => GraphActivityEvent[];
  deriveActivityLayerData: (input: GraphActivityInput) => GraphActivityLayerData;
  deriveStatusPulseNodes: (input: GraphStatusPulseInput) => ActivityPulse[];
};

export type GraphAffordanceRegistry = Partial<{
  labels: GraphLabelAffordance;
  activity: GraphActivityAffordance;
}>;

type GraphAffordanceKey = keyof Required<GraphAffordanceRegistry>;

type GraphAffordanceWindow = Window & {
  __techTreeGraphAffordances?: GraphAffordanceRegistry;
  __techTreeGraphAffordanceAssets?: Partial<Record<GraphAffordanceKey, Promise<void>>>;
};

function affordanceWindow(): GraphAffordanceWindow {
  return window as GraphAffordanceWindow;
}

export function registerGraphAffordances(affordances: GraphAffordanceRegistry) {
  const globalWindow = affordanceWindow();
  globalWindow.__techTreeGraphAffordances = {
    ...(globalWindow.__techTreeGraphAffordances || {}),
    ...affordances,
  };
}

export function graphAffordances(): GraphAffordanceRegistry {
  return affordanceWindow().__techTreeGraphAffordances || {};
}

export function ensureGraphAffordance(
  key: GraphAffordanceKey,
  assetPath: string,
): Promise<void> {
  const registry = graphAffordances();
  if (registry[key]) {
    return Promise.resolve();
  }

  const globalWindow = affordanceWindow();
  const pending = globalWindow.__techTreeGraphAffordanceAssets?.[key];
  if (pending) {
    return pending;
  }

  const promise = new Promise<void>((resolve, reject) => {
    const selector = `script[data-tech-tree-graph-affordance="${key}"]`;
    const existing = document.querySelector<HTMLScriptElement>(selector);

    if (existing) {
      existing.addEventListener("load", () => resolve(), { once: true });
      existing.addEventListener(
        "error",
        () => reject(new Error(`failed to load graph affordance ${key}`)),
        { once: true },
      );
      return;
    }

    const script = document.createElement("script");
    script.defer = true;
    script.src = assetPath;
    script.dataset.techTreeGraphAffordance = key;
    script.addEventListener("load", () => resolve(), { once: true });
    script.addEventListener(
      "error",
      () => reject(new Error(`failed to load graph affordance ${key}`)),
      { once: true },
    );
    document.head.appendChild(script);
  }).then(() => {
    if (!graphAffordances()[key]) {
      throw new Error(`graph affordance "${key}" did not register after loading ${assetPath}`);
    }
  });

  globalWindow.__techTreeGraphAffordanceAssets = {
    ...(globalWindow.__techTreeGraphAffordanceAssets || {}),
    [key]: promise,
  };

  return promise;
}
