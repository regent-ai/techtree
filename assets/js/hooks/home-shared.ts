export type AnimationHandle = {
  pause?: () => void;
  cancel?: () => void;
};

type VariantNode = {
  kind: string;
};

export function parseJson<T>(value: string | undefined, fallback: T): T {
  if (!value) return fallback;

  try {
    return JSON.parse(value) as T;
  } catch (_error) {
    return fallback;
  }
}

export function readBool(value: string | undefined): boolean {
  return value === "true";
}

export function readNodeId(value: string | undefined): number | null {
  if (!value) return null;

  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : null;
}

export function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

export function variantForNode<T extends VariantNode>(
  node: T,
): "primary" | "alt" {
  return node.kind === "result" ||
      node.kind === "skill" ||
      node.kind === "synthesis"
    ? "alt"
    : "primary";
}

export function pauseMotion(motion: AnimationHandle | null | undefined) {
  motion?.pause?.();
  motion?.cancel?.();
}
