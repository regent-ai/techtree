import type { Hook, HookContext } from "phoenix_live_view";

import { animate, stagger } from "../../vendor/anime.esm.js";
import {
  type AnimationHandle,
  parseJson,
  readBool,
  readNodeId,
  variantForNode,
} from "./home-shared";

type GraphNode = {
  id: number;
  parent_id: number | null;
  depth: number;
  title: string;
  path?: string | null;
  kind: string;
  seed: string;
  child_count: number;
  watcher_count: number;
  comment_count: number;
  summary?: string | null;
  status?: string;
  creator_address?: string | null;
};

function preferredGridOffset(viewport: HTMLElement): GridOffset {
  const width = viewport.clientWidth;
  const height = viewport.clientHeight;
  const yBias =
    width <= 700 ? -height * 0.08 : width <= 1024 ? -height * 0.14 : -height * 0.19;

  return {
    x: 0,
    y: Math.round(yBias),
  };
}

function setPreferredGridOffset(runtime: GridRuntime) {
  const preferred = preferredGridOffset(runtime.viewport);
  runtime.offset = { ...preferred };
  runtime.restPos = { ...preferred };
  runtime.offsetOrigin = { ...preferred };
}

type GridPayload = {
  nodes: GraphNode[];
  seedOrder: string[];
  seedLabels: Record<string, string>;
  seedNotes: Record<string, string>;
};

type GridOffset = {
  x: number;
  y: number;
};

type CubeCoordinate = {
  q: number;
  r: number;
  s: number;
};

type VisibleHex = {
  cube: CubeCoordinate;
  index: number;
  pixelX: number;
  pixelY: number;
};

type HexMetrics = {
  width: number;
  height: number;
  outerRadius: number;
  innerRadius: number;
  hexWidth: number;
  hexHeight: number;
};

type GridRuntime = {
  host: HTMLElement;
  viewport: HTMLElement;
  plane: HTMLElement;
  itemsHost: HTMLElement;
  payloadKey: string;
  payload: GridPayload;
  orderedNodes: GraphNode[];
  selectedNodeId: number | null;
  active: boolean;
  offset: GridOffset;
  restPos: GridOffset;
  velocity: GridOffset;
  velocityHistory: GridOffset[];
  pointerOrigin: GridOffset;
  offsetOrigin: GridOffset;
  lastPos: GridOffset;
  lastMoveTime: number;
  lastAnimationTime: number;
  isDragging: boolean;
  isMoving: boolean;
  movedDuringPointer: boolean;
  pointerId: number | null;
  animationFrame: number | null;
  stopMovingTimer: number | null;
  clickSuppressUntil: number;
  lastRenderedSignature: string;
  transitioning: boolean;
  transitionMode: "drilldown" | "return" | null;
  transitionOrigin: GridOffset | null;
  resizeObserver: ResizeObserver;
  onPointerDown: (event: PointerEvent) => void;
  onPointerMove: (event: PointerEvent) => void;
  onPointerUp: (event: PointerEvent) => void;
  onClick: (event: MouseEvent) => void;
  onWheel: (event: WheelEvent) => void;
};

type GridHook = HookContext &
  Hook & {
    __grid?: GridRuntime;
  };

const gridMinVelocity = 0.2;
const gridUpdateInterval = 16;
const gridVelocityHistorySize = 5;
const gridFriction = 0.9;
const gridVelocityThreshold = 0.3;
const defaultGridPayload: GridPayload = {
  nodes: [],
  seedOrder: [],
  seedLabels: {},
  seedNotes: {},
};
const cubeDirections: readonly CubeCoordinate[] = [
  { q: 1, r: 0, s: -1 },
  { q: 1, r: -1, s: 0 },
  { q: 0, r: -1, s: 1 },
  { q: -1, r: 0, s: 1 },
  { q: -1, r: 1, s: 0 },
  { q: 0, r: 1, s: -1 },
];

function distanceBetween(a: GridOffset, b: GridOffset): number {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  return Math.sqrt(dx * dx + dy * dy);
}

function cube(q: number, r: number, s: number): CubeCoordinate {
  return { q, r, s };
}

function cubeAdd(left: CubeCoordinate, right: CubeCoordinate): CubeCoordinate {
  return cube(left.q + right.q, left.r + right.r, left.s + right.s);
}

function cubeScale(source: CubeCoordinate, factor: number): CubeCoordinate {
  return cube(source.q * factor, source.r * factor, source.s * factor);
}

function cubeEqual(left: CubeCoordinate, right: CubeCoordinate): boolean {
  return left.q === right.q && left.r === right.r && left.s === right.s;
}

function cubeNeighbor(
  source: CubeCoordinate,
  directionIndex: number,
): CubeCoordinate {
  return cubeAdd(
    source,
    cubeDirections[directionIndex % cubeDirections.length]!,
  );
}

function cubeDistance(left: CubeCoordinate, right: CubeCoordinate): number {
  return Math.max(
    Math.abs(left.q - right.q),
    Math.abs(left.r - right.r),
    Math.abs(left.s - right.s),
  );
}

function roundCube(q: number, r: number, s: number): CubeCoordinate {
  let roundedQ = Math.round(q);
  let roundedR = Math.round(r);
  let roundedS = Math.round(s);

  const qDiff = Math.abs(roundedQ - q);
  const rDiff = Math.abs(roundedR - r);
  const sDiff = Math.abs(roundedS - s);

  if (qDiff > rDiff && qDiff > sDiff) {
    roundedQ = -roundedR - roundedS;
  } else if (rDiff > sDiff) {
    roundedR = -roundedQ - roundedS;
  } else {
    roundedS = -roundedQ - roundedR;
  }

  return cube(roundedQ, roundedR, roundedS);
}

function readGridPayload(value: string | undefined): GridPayload {
  return parseJson<GridPayload>(value, defaultGridPayload);
}

function gridSeedRank(payload: GridPayload, seed: string): number {
  const index = payload.seedOrder.indexOf(seed);
  return index === -1 ? payload.seedOrder.length + 1_000 : index;
}

function parsePathSegments(node: GraphNode): number[] {
  const fallback = [node.id];
  const source = node.path?.trim();
  if (!source) return fallback;

  const segments = source
    .split(".")
    .map((segment) => Number.parseInt(segment.replace(/^n/, ""), 10))
    .filter((segment) => Number.isFinite(segment));

  return segments.length > 0 ? segments : fallback;
}

function compareSegments(left: number[], right: number[]): number {
  const maxLength = Math.max(left.length, right.length);

  for (let index = 0; index < maxLength; index += 1) {
    const leftValue = left[index];
    const rightValue = right[index];

    if (leftValue == null) return -1;
    if (rightValue == null) return 1;
    if (leftValue !== rightValue) return leftValue - rightValue;
  }

  return 0;
}

function orderGridNodes(payload: GridPayload): GraphNode[] {
  return [...payload.nodes].sort((left, right) => {
    if (left.depth !== right.depth) return left.depth - right.depth;

    const seedRankDiff =
      gridSeedRank(payload, left.seed) - gridSeedRank(payload, right.seed);
    if (seedRankDiff !== 0) return seedRankDiff;

    const segmentDiff = compareSegments(
      parsePathSegments(left),
      parsePathSegments(right),
    );
    if (segmentDiff !== 0) return segmentDiff;

    return left.id - right.id;
  });
}

function readHexOuterRadius(host: HTMLElement): number {
  const rawValue = getComputedStyle(host)
    .getPropertyValue("--fp-grid-hex-size")
    .trim();
  const parsed = Number.parseFloat(rawValue);
  return Number.isFinite(parsed) ? parsed : 96;
}

function hexMetrics(runtime: GridRuntime): HexMetrics {
  const rect = runtime.viewport.getBoundingClientRect();
  const outerRadius = readHexOuterRadius(runtime.host);
  const innerRadius = (Math.sqrt(3) / 2) * outerRadius;

  return {
    width: rect.width,
    height: rect.height,
    outerRadius,
    innerRadius,
    hexWidth: outerRadius * 2,
    hexHeight: innerRadius * 2,
  };
}

function cubeToPixel(source: CubeCoordinate, metrics: HexMetrics): GridOffset {
  return {
    x: metrics.outerRadius * 1.5 * source.q,
    y: metrics.hexHeight * (source.r + source.q / 2),
  };
}

function pixelToCube(source: GridOffset, metrics: HexMetrics): CubeCoordinate {
  const q = ((2 / 3) * source.x) / metrics.outerRadius;
  const r =
    ((Math.sqrt(3) / 3) * source.y - source.x / 3) / metrics.outerRadius;
  return roundCube(q, r, -q - r);
}

function cubeRing(center: CubeCoordinate, radius: number): CubeCoordinate[] {
  if (radius === 0) return [center];

  const result: CubeCoordinate[] = [];
  let current = cubeAdd(center, cubeScale(cubeDirections[4]!, radius));

  for (let side = 0; side < 6; side += 1) {
    for (let step = 0; step < radius; step += 1) {
      result.push(current);
      current = cubeNeighbor(current, side);
    }
  }

  return result;
}

function cubeSpiral(center: CubeCoordinate, radius: number): CubeCoordinate[] {
  const result: CubeCoordinate[] = [center];

  for (let ring = 1; ring <= radius; ring += 1) {
    result.push(...cubeRing(center, ring));
  }

  return result;
}

function gridIndexForCube(source: CubeCoordinate): number {
  if (source.q === 0 && source.r === 0 && source.s === 0) return 0;

  const layer = Math.max(
    Math.abs(source.q),
    Math.abs(source.r),
    Math.abs(source.s),
  );
  const ringStartIndex = 1 + 3 * (layer - 1) * layer;
  const ring = cubeRing(cube(0, 0, 0), layer);

  for (let offset = 0; offset < ring.length; offset += 1) {
    if (cubeEqual(ring[offset]!, source)) {
      return ringStartIndex + offset;
    }
  }

  return ringStartIndex;
}

function syncGridTransform(runtime: GridRuntime) {
  runtime.plane.style.transform = `translate3d(${runtime.offset.x}px, ${runtime.offset.y}px, 0)`;
}

function setGridMoving(runtime: GridRuntime, moving: boolean) {
  runtime.isMoving = moving;
  runtime.host.dataset.gridMoving = moving ? "true" : "false";
}

function clearGridStopTimer(runtime: GridRuntime) {
  if (runtime.stopMovingTimer != null) {
    window.clearTimeout(runtime.stopMovingTimer);
    runtime.stopMovingTimer = null;
  }
}

function scheduleGridIdle(runtime: GridRuntime) {
  clearGridStopTimer(runtime);

  runtime.stopMovingTimer = window.setTimeout(() => {
    if (!runtime.isDragging && runtime.animationFrame == null) {
      runtime.restPos = { ...runtime.offset };
      setGridMoving(runtime, false);
      renderGrid(runtime, true);
    }
  }, 180);
}

function stopGridMotion(runtime: GridRuntime) {
  if (runtime.animationFrame != null) {
    cancelAnimationFrame(runtime.animationFrame);
    runtime.animationFrame = null;
  }
}

function gridRootLabel(payload: GridPayload, node: GraphNode): string {
  return payload.seedLabels[node.seed] || node.title;
}

function gridNodeTitle(payload: GridPayload, node: GraphNode): string {
  return node.parent_id == null ? gridRootLabel(payload, node) : node.title;
}

function gridCoordLabel(source: CubeCoordinate): string {
  return `q${source.q >= 0 ? "+" : ""}${source.q} r${source.r >= 0 ? "+" : ""}${source.r} s${source.s >= 0 ? "+" : ""}${source.s}`;
}

function gridTransitionCenter(runtime: GridRuntime): GridOffset {
  const rect = runtime.viewport.getBoundingClientRect();

  return {
    x: rect.left + rect.width / 2,
    y: rect.top + rect.height * 0.4,
  };
}

function animateGridCards(host: HTMLElement) {
  const cards = Array.from(
    host.querySelectorAll<HTMLElement>("[data-grid-card]"),
  );
  if (cards.length === 0) return;

  animate(cards, {
    opacity: [0, 1],
    translateY: [18, 0],
    scale: [0.94, 1],
    delay: (_target, index) => Math.min(index * 12, 180),
    duration: 340,
    ease: "outExpo",
  });
}

function waitForAnimation(animation: AnimationHandle | null | undefined) {
  const candidate = animation as AnimationHandle & {
    then?: (callback: () => void) => Promise<unknown>;
  };

  if (typeof candidate?.then === "function") {
    return candidate.then(() => undefined);
  }

  return Promise.resolve();
}

function pulseSelectedGridCard(
  host: HTMLElement,
  selectedNodeId: number | null,
) {
  if (selectedNodeId == null) return;

  const selected = host.querySelector<HTMLElement>(
    `[data-node-id="${selectedNodeId}"] [data-grid-card]`,
  );
  if (!selected) return;

  animate(selected, {
    scale: [1, 1.035, 1],
    duration: 420,
    ease: "outExpo",
  });
}

function animateGridArrival(runtime: GridRuntime) {
  const cards = Array.from(runtime.itemsHost.querySelectorAll<HTMLElement>(".fp-grid-item"));
  if (cards.length === 0) return;

  const origin = runtime.transitionOrigin ?? gridTransitionCenter(runtime);
  const mode = runtime.transitionMode ?? "drilldown";

  animate(cards, {
    opacity: [0, 1],
    scale: mode === "drilldown" ? [0.54, 1] : [1.16, 1],
    rotate: (target: unknown) => {
      const center = elementCenter(target as HTMLElement);
      const spin = center.x >= origin.x ? 10 : -10;
      return mode === "drilldown" ? [spin, 0] : [spin * -1, 0];
    },
    translateX: (target: unknown) => {
      const center = elementCenter(target as HTMLElement);
      const dx = center.x - origin.x;
      return mode === "drilldown" ? [dx * -0.16, 0] : [dx * 0.12, 0];
    },
    translateY: (target: unknown) => {
      const center = elementCenter(target as HTMLElement);
      const dy = center.y - origin.y;
      return mode === "drilldown" ? [dy * -0.16, 0] : [dy * 0.12, 0];
    },
    delay: stagger(mode === "drilldown" ? 18 : 12, { from: "center", start: 30 }),
    duration: mode === "drilldown" ? 520 : 440,
    ease: mode === "drilldown" ? "outExpo" : "outCubic",
  });
}

function buildGridNodeCell(
  runtime: GridRuntime,
  node: GraphNode,
  gridIndex: number,
  cubeCoord: CubeCoordinate,
): HTMLElement {
  const button = document.createElement("button");
  const selected = runtime.selectedNodeId === node.id;
  const isRoot = node.parent_id == null;

  button.type = "button";
  button.className = "fp-grid-item";
  button.dataset.nodeId = String(node.id);
  button.dataset.gridIndex = String(gridIndex);
  button.dataset.cube = `${cubeCoord.q},${cubeCoord.r},${cubeCoord.s}`;
  button.setAttribute(
    "aria-label",
    `${gridNodeTitle(runtime.payload, node)} at ${gridCoordLabel(cubeCoord)}`,
  );

  const card = document.createElement("article");
  card.className = "fp-grid-card";
  card.dataset.gridCard = "true";
  if (selected) card.classList.add("is-selected");
  if (isRoot) card.classList.add("is-root");
  if (variantForNode(node) === "alt") card.classList.add("is-alt");

  const title = document.createElement("h3");
  title.className = "fp-grid-card-title";
  title.textContent = gridNodeTitle(runtime.payload, node);
  card.append(title);
  button.append(card);

  return button;
}

function buildGridFutureCell(
  gridIndex: number,
  cubeCoord: CubeCoordinate,
): HTMLElement {
  const shell = document.createElement("div");
  shell.className = "fp-grid-item";
  shell.dataset.gridIndex = String(gridIndex);
  shell.dataset.cube = `${cubeCoord.q},${cubeCoord.r},${cubeCoord.s}`;

  const card = document.createElement("article");
  card.className = "fp-grid-card is-future";
  card.dataset.gridCard = "true";

  const title = document.createElement("h3");
  title.className = "fp-grid-card-title";
  title.textContent = "Future node";
  card.append(title);
  shell.append(card);

  return shell;
}

function visibleHexes(runtime: GridRuntime): VisibleHex[] {
  const metrics = hexMetrics(runtime);
  const worldCenter = pixelToCube(
    { x: -runtime.offset.x, y: -runtime.offset.y },
    metrics,
  );
  const corners = [
    pixelToCube(
      {
        x: -runtime.offset.x - metrics.width / 2,
        y: -runtime.offset.y - metrics.height / 2,
      },
      metrics,
    ),
    pixelToCube(
      {
        x: -runtime.offset.x + metrics.width / 2,
        y: -runtime.offset.y - metrics.height / 2,
      },
      metrics,
    ),
    pixelToCube(
      {
        x: -runtime.offset.x + metrics.width / 2,
        y: -runtime.offset.y + metrics.height / 2,
      },
      metrics,
    ),
    pixelToCube(
      {
        x: -runtime.offset.x - metrics.width / 2,
        y: -runtime.offset.y + metrics.height / 2,
      },
      metrics,
    ),
  ];

  const radius =
    Math.max(...corners.map((corner) => cubeDistance(worldCenter, corner))) + 3;

  return cubeSpiral(worldCenter, radius)
    .map((cubeCoord) => {
      const pixel = cubeToPixel(cubeCoord, metrics);
      const screenX = pixel.x + metrics.width / 2;
      const screenY = pixel.y + metrics.height / 2;

      return {
        cube: cubeCoord,
        index: gridIndexForCube(cubeCoord),
        pixelX: screenX,
        pixelY: screenY,
      };
    })
    .filter(
      (entry) =>
        entry.pixelX >= -metrics.hexWidth &&
        entry.pixelX <= metrics.width + metrics.hexWidth &&
        entry.pixelY >= -metrics.hexHeight &&
        entry.pixelY <= metrics.height + metrics.hexHeight,
    )
    .sort((left, right) => left.index - right.index);
}

function renderGrid(runtime: GridRuntime, force = false, animateFresh = false) {
  syncGridTransform(runtime);

  const metrics = hexMetrics(runtime);
  const centerCube = pixelToCube(
    { x: -runtime.offset.x, y: -runtime.offset.y },
    metrics,
  );
  const signature = [
    runtime.payloadKey,
    runtime.selectedNodeId ?? "none",
    centerCube.q,
    centerCube.r,
    centerCube.s,
    Math.round(metrics.width),
    Math.round(metrics.height),
  ].join("|");

  if (!force && signature === runtime.lastRenderedSignature) return;

  runtime.lastRenderedSignature = signature;

  const fragment = document.createDocumentFragment();

  for (const hex of visibleHexes(runtime)) {
    const node = runtime.orderedNodes[hex.index] ?? null;
    const item = node
      ? buildGridNodeCell(runtime, node, hex.index, hex.cube)
      : buildGridFutureCell(hex.index, hex.cube);

    item.style.width = `${metrics.hexWidth}px`;
    item.style.height = `${metrics.hexHeight}px`;
    item.style.transform = `translate3d(${hex.pixelX}px, ${hex.pixelY}px, 0)`;
    item.style.marginLeft = `${-metrics.hexWidth / 2}px`;
    item.style.marginTop = `${-metrics.hexHeight / 2}px`;

    fragment.appendChild(item);
  }

  runtime.itemsHost.replaceChildren(fragment);

  if (animateFresh) {
    if (runtime.transitionMode) {
      animateGridArrival(runtime);
      runtime.transitionMode = null;
      runtime.transitionOrigin = null;
    } else {
      animateGridCards(runtime.itemsHost);
    }
  }
}

function stepGridMotion(runtime: GridRuntime, timestamp: number) {
  const deltaTime =
    runtime.lastAnimationTime === 0
      ? gridUpdateInterval
      : timestamp - runtime.lastAnimationTime;

  if (deltaTime >= gridUpdateInterval) {
    const speed = Math.sqrt(runtime.velocity.x ** 2 + runtime.velocity.y ** 2);

    if (speed < gridMinVelocity) {
      runtime.velocity = { x: 0, y: 0 };
      runtime.animationFrame = null;
      scheduleGridIdle(runtime);
      return;
    }

    let deceleration = gridFriction;
    if (speed < gridVelocityThreshold) {
      deceleration = gridFriction * (speed / gridVelocityThreshold);
    }

    const deltaFactor = Math.max(deltaTime / gridUpdateInterval, 1);
    runtime.offset = {
      x: runtime.offset.x + runtime.velocity.x * deltaFactor,
      y: runtime.offset.y + runtime.velocity.y * deltaFactor,
    };
    runtime.velocity = {
      x: runtime.velocity.x * Math.pow(deceleration, deltaFactor),
      y: runtime.velocity.y * Math.pow(deceleration, deltaFactor),
    };
    runtime.lastAnimationTime = timestamp;

    renderGrid(runtime);
  }

  runtime.animationFrame = requestAnimationFrame((nextTimestamp) =>
    stepGridMotion(runtime, nextTimestamp),
  );
}

function beginGridMotion(runtime: GridRuntime) {
  stopGridMotion(runtime);
  clearGridStopTimer(runtime);
  setGridMoving(runtime, true);
  runtime.lastAnimationTime = 0;
  runtime.animationFrame = requestAnimationFrame((timestamp) =>
    stepGridMotion(runtime, timestamp),
  );
}

function updateGridOffset(runtime: GridRuntime, nextOffset: GridOffset) {
  runtime.offset = nextOffset;
  clearGridStopTimer(runtime);
  setGridMoving(runtime, true);
  renderGrid(runtime);
  scheduleGridIdle(runtime);
}

function handleGridPointerDown(runtime: GridRuntime, event: PointerEvent) {
  if (!runtime.active) return;

  stopGridMotion(runtime);
  clearGridStopTimer(runtime);
  runtime.viewport.setPointerCapture(event.pointerId);
  runtime.pointerId = event.pointerId;
  runtime.isDragging = true;
  runtime.movedDuringPointer = false;
  runtime.pointerOrigin = { x: event.clientX, y: event.clientY };
  runtime.offsetOrigin = { ...runtime.offset };
  runtime.lastPos = { x: event.clientX, y: event.clientY };
  runtime.lastMoveTime = performance.now();
  runtime.velocity = { x: 0, y: 0 };
  runtime.velocityHistory = [];
  setGridMoving(runtime, true);
}

function handleGridPointerMove(runtime: GridRuntime, event: PointerEvent) {
  if (
    !runtime.active ||
    !runtime.isDragging ||
    runtime.pointerId !== event.pointerId
  )
    return;

  event.preventDefault();

  const now = performance.now();
  const current = { x: event.clientX, y: event.clientY };
  const nextOffset = {
    x: runtime.offsetOrigin.x + (current.x - runtime.pointerOrigin.x),
    y: runtime.offsetOrigin.y + (current.y - runtime.pointerOrigin.y),
  };

  const timeDelta = now - runtime.lastMoveTime;
  const rawVelocity = {
    x: (current.x - runtime.lastPos.x) / (timeDelta || 1),
    y: (current.y - runtime.lastPos.y) / (timeDelta || 1),
  };

  runtime.velocityHistory = [...runtime.velocityHistory, rawVelocity].slice(
    -gridVelocityHistorySize,
  );
  runtime.velocity = runtime.velocityHistory.reduce(
    (acc, velocity) => ({
      x: acc.x + velocity.x / runtime.velocityHistory.length,
      y: acc.y + velocity.y / runtime.velocityHistory.length,
    }),
    { x: 0, y: 0 },
  );

  runtime.movedDuringPointer ||=
    distanceBetween(runtime.pointerOrigin, current) > 6;
  runtime.lastPos = current;
  runtime.lastMoveTime = now;

  updateGridOffset(runtime, nextOffset);
}

function handleGridPointerUp(runtime: GridRuntime, event: PointerEvent) {
  if (runtime.pointerId !== event.pointerId) return;

  if (runtime.viewport.hasPointerCapture(event.pointerId)) {
    runtime.viewport.releasePointerCapture(event.pointerId);
  }

  runtime.pointerId = null;
  runtime.isDragging = false;

  const speed = Math.sqrt(runtime.velocity.x ** 2 + runtime.velocity.y ** 2);
  if (runtime.movedDuringPointer || speed >= gridMinVelocity) {
    runtime.clickSuppressUntil = performance.now() + 220;
    beginGridMotion(runtime);
    return;
  }

  scheduleGridIdle(runtime);
}

function handleGridClick(
  hook: GridHook,
  runtime: GridRuntime,
  event: MouseEvent,
) {
  if (!runtime.active) return;

  const target = event.target as HTMLElement | null;
  const action = target?.closest<HTMLElement>("[data-grid-action]");

  if (action) {
    if (runtime.transitioning) return;

    const actionType = action.dataset.gridAction;
    if (actionType === "drilldown") {
      const nodeId = readNodeId(action.dataset.nodeId);
      if (nodeId == null) return;
      const sourceItem =
        runtime.itemsHost.querySelector<HTMLElement>(`[data-node-id="${nodeId}"]`) ??
        action.closest<HTMLElement>("[data-node-id]");

      event.preventDefault();
      event.stopPropagation();
      runtime.transitioning = true;
      runtime.transitionMode = "drilldown";
      runtime.transitionOrigin = sourceItem
        ? elementCenter(sourceItem)
        : gridTransitionCenter(runtime);

      animateGridDrilldown(runtime, nodeId).then(() => {
        hook.pushEvent("drilldown-grid-node", { node_id: nodeId });
      });

      return;
    }

    if (actionType === "return") {
      event.preventDefault();
      event.stopPropagation();
      runtime.transitioning = true;
      runtime.transitionMode = "return";
      runtime.transitionOrigin = gridTransitionCenter(runtime);

      animateGridReturn(runtime).then(() => {
        hook.pushEvent("return-grid-level", {});
      });
    }

    return;
  }

  if (performance.now() < runtime.clickSuppressUntil) return;

  const nodeEl = target?.closest<HTMLElement>("[data-node-id]");
  const nodeId = readNodeId(nodeEl?.dataset.nodeId);

  if (nodeId == null) return;

  event.preventDefault();
  event.stopPropagation();

  runtime.selectedNodeId = nodeId;
  hook.pushEvent("open-grid-node", { node_id: nodeId });
  renderGrid(runtime, true);
  pulseSelectedGridCard(runtime.itemsHost, nodeId);
}

function elementCenter(source: HTMLElement): GridOffset {
  const rect = source.getBoundingClientRect();

  return {
    x: rect.left + rect.width / 2,
    y: rect.top + rect.height / 2,
  };
}

function swirlVector(origin: GridOffset, target: GridOffset): GridOffset {
  const dx = target.x - origin.x;
  const dy = target.y - origin.y;
  const distance = Math.hypot(dx, dy) || 1;
  const angle = Math.atan2(dy, dx) + Math.PI * 0.72;
  const radius = distance * 0.78 + 38;

  return {
    x: Math.cos(angle) * radius,
    y: Math.sin(angle) * radius,
  };
}

async function animateGridDrilldown(runtime: GridRuntime, selectedNodeId: number) {
  const items = Array.from(runtime.itemsHost.querySelectorAll<HTMLElement>(".fp-grid-item"));
  if (items.length === 0) return;

  const selectedItem = runtime.itemsHost.querySelector<HTMLElement>(
    `[data-node-id="${selectedNodeId}"]`,
  );

  const origin = selectedItem
    ? elementCenter(selectedItem)
    : {
        x: runtime.viewport.getBoundingClientRect().left + runtime.viewport.clientWidth / 2,
        y: runtime.viewport.getBoundingClientRect().top + runtime.viewport.clientHeight / 2,
      };

  const others = items.filter((item) => item !== selectedItem);

  if (others.length > 0) {
    const othersMotion = animate(others, {
      opacity: [1, 0],
      scale: [1, 0.34],
      rotate: (target: unknown) => {
        const center = elementCenter(target as HTMLElement);
        return [0, center.x >= origin.x ? 150 : -150];
      },
      translateX: (target: unknown) => swirlVector(origin, elementCenter(target as HTMLElement)).x,
      translateY: (target: unknown) => swirlVector(origin, elementCenter(target as HTMLElement)).y,
      delay: stagger(22, { start: 20 }),
      duration: 720,
      ease: "inBack",
    });

    await waitForAnimation(othersMotion);
  }

  if (selectedItem) {
    const selectedMotion = animate(selectedItem, {
      scale: [1, 1.04, 0.9],
      opacity: [1, 0.18],
      duration: 420,
      ease: "inOutSine",
    });

    await waitForAnimation(selectedMotion);
  }
}

async function animateGridReturn(runtime: GridRuntime) {
  const items = Array.from(runtime.itemsHost.querySelectorAll<HTMLElement>(".fp-grid-item"));
  if (items.length === 0) return;

  const origin = {
    x: runtime.viewport.getBoundingClientRect().left + runtime.viewport.clientWidth / 2,
    y: runtime.viewport.getBoundingClientRect().top + runtime.viewport.clientHeight / 2,
  };

  const motion = animate(items, {
    opacity: [1, 0],
    scale: [1, 0.42],
    rotate: (target: unknown) => {
      const center = elementCenter(target as HTMLElement);
      return [0, center.x >= origin.x ? 120 : -120];
    },
    translateX: (target: unknown) => swirlVector(origin, elementCenter(target as HTMLElement)).x * 0.72,
    translateY: (target: unknown) => swirlVector(origin, elementCenter(target as HTMLElement)).y * 0.72,
    delay: stagger(18, { start: 12 }),
    duration: 460,
    ease: "inQuad",
  });

  await waitForAnimation(motion);
}

function handleGridWheel(runtime: GridRuntime, event: WheelEvent) {
  if (!runtime.active) return;

  event.preventDefault();
  stopGridMotion(runtime);
  runtime.isDragging = false;
  runtime.pointerId = null;
  runtime.velocity = { x: 0, y: 0 };

  updateGridOffset(runtime, {
    x: runtime.offset.x - event.deltaX,
    y: runtime.offset.y - event.deltaY,
  });
}

function updateGridPayload(
  runtime: GridRuntime,
  payloadKey: string,
  selectedNodeId: number | null,
) {
  const nextPayload = readGridPayload(payloadKey);
  runtime.payloadKey = payloadKey;
  runtime.payload = nextPayload;
  runtime.orderedNodes = orderGridNodes(nextPayload);
  runtime.selectedNodeId = selectedNodeId;
  setPreferredGridOffset(runtime);
  runtime.lastRenderedSignature = "";
  renderGrid(runtime, true, true);
}

export const FrontpageThingsGrid: Hook = {
  mounted() {
    const hook = this as GridHook;
    const viewport = this.el.querySelector<HTMLElement>("[data-grid-viewport]");
    const plane = this.el.querySelector<HTMLElement>("[data-grid-plane]");
    const itemsHost = this.el.querySelector<HTMLElement>("[data-grid-items]");

    if (!viewport || !plane || !itemsHost) return;

    const payloadKey =
      this.el.dataset.grid ?? JSON.stringify(defaultGridPayload);
    const payload = readGridPayload(payloadKey);
    const initialOffset = preferredGridOffset(viewport);

    const runtime: GridRuntime = {
      host: this.el as HTMLElement,
      viewport,
      plane,
      itemsHost,
      payloadKey,
      payload,
      orderedNodes: orderGridNodes(payload),
      selectedNodeId: readNodeId(this.el.dataset.selectedNodeId),
      active: readBool(this.el.dataset.active),
      offset: initialOffset,
      restPos: { ...initialOffset },
      velocity: { x: 0, y: 0 },
      velocityHistory: [],
      pointerOrigin: { x: 0, y: 0 },
      offsetOrigin: { ...initialOffset },
      lastPos: { x: 0, y: 0 },
      lastMoveTime: 0,
      lastAnimationTime: 0,
      isDragging: false,
      isMoving: false,
      movedDuringPointer: false,
      pointerId: null,
      animationFrame: null,
      stopMovingTimer: null,
      clickSuppressUntil: 0,
      lastRenderedSignature: "",
      transitioning: false,
      transitionMode: null,
      transitionOrigin: null,
      resizeObserver: new ResizeObserver(() => {
        if (!runtime.isDragging && runtime.animationFrame == null) {
          setPreferredGridOffset(runtime);
        }
        runtime.lastRenderedSignature = "";
        renderGrid(runtime, true);
      }),
      onPointerDown: (event) => handleGridPointerDown(runtime, event),
      onPointerMove: (event) => handleGridPointerMove(runtime, event),
      onPointerUp: (event) => handleGridPointerUp(runtime, event),
      onClick: (event) => handleGridClick(hook, runtime, event),
      onWheel: (event) => handleGridWheel(runtime, event),
    };

    viewport.addEventListener("pointerdown", runtime.onPointerDown);
    viewport.addEventListener("pointermove", runtime.onPointerMove);
    viewport.addEventListener("pointerup", runtime.onPointerUp);
    viewport.addEventListener("pointercancel", runtime.onPointerUp);
    runtime.host.addEventListener("click", runtime.onClick);
    viewport.addEventListener("wheel", runtime.onWheel, { passive: false });
    runtime.resizeObserver.observe(viewport);

    hook.__grid = runtime;

    renderGrid(runtime, true, true);
    if (runtime.selectedNodeId != null) {
      pulseSelectedGridCard(runtime.itemsHost, runtime.selectedNodeId);
    }
  },

  updated() {
    const hook = this as GridHook;
    const runtime = hook.__grid;

    if (!runtime) return;

    const nextPayloadKey =
      this.el.dataset.grid ?? JSON.stringify(defaultGridPayload);
    const nextSelectedNodeId = readNodeId(this.el.dataset.selectedNodeId);
    const nextActive = readBool(this.el.dataset.active);
    const payloadChanged = nextPayloadKey !== runtime.payloadKey;
    const selectedChanged = nextSelectedNodeId !== runtime.selectedNodeId;

    runtime.active = nextActive;

    if (payloadChanged) {
      runtime.transitioning = false;
      updateGridPayload(runtime, nextPayloadKey, nextSelectedNodeId);
      return;
    }

    runtime.selectedNodeId = nextSelectedNodeId;

    if (!runtime.active) {
      stopGridMotion(runtime);
      runtime.isDragging = false;
      runtime.pointerId = null;
    }

    renderGrid(runtime, selectedChanged);

    if (runtime.active && selectedChanged) {
      pulseSelectedGridCard(runtime.itemsHost, runtime.selectedNodeId);
    }
  },

  destroyed() {
    const hook = this as GridHook;
    const runtime = hook.__grid;

    if (!runtime) return;

    stopGridMotion(runtime);
    clearGridStopTimer(runtime);
    runtime.resizeObserver.disconnect();
    runtime.viewport.removeEventListener("pointerdown", runtime.onPointerDown);
    runtime.viewport.removeEventListener("pointermove", runtime.onPointerMove);
    runtime.viewport.removeEventListener("pointerup", runtime.onPointerUp);
    runtime.viewport.removeEventListener("pointercancel", runtime.onPointerUp);
    runtime.host.removeEventListener("click", runtime.onClick);
    runtime.viewport.removeEventListener("wheel", runtime.onWheel);
  },
};
