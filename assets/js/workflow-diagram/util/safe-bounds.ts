import type { ReactFlowInstance, Rect, Node } from '@xyflow/react';
import { getNodesBounds as rawGetNodesBounds } from '@xyflow/react';

type MaybePos = { position?: { x?: number; y?: number } };
type XY = { position: { x: number; y: number } };

/** true if node has finite x/y */
export const hasXY = (n: MaybePos | null | undefined): n is XY =>
  !!n &&
  !!n.position &&
  Number.isFinite(n.position.x) &&
  Number.isFinite(n.position.y);

/** Returns bounds or null if no nodes have valid positions */
export function safeGetNodesBounds(
  nodes: MaybePos[],
  getNodesBounds = rawGetNodesBounds
): Rect | null {
  const withPos = nodes.filter(hasXY) as unknown as Node[];
  return withPos.length ? getNodesBounds(withPos) : null;
}

/** Fits only when bounds can be computed. Always returns a Promise. */
export function safeFitBounds(
  flow: ReactFlowInstance | undefined,
  nodes: MaybePos[],
  opts: { duration?: number; padding?: number } = {}
): Promise<void> {
  if (!flow) return Promise.resolve();
  const b = safeGetNodesBounds(nodes);
  return b ? flow.fitBounds(b, opts) : Promise.resolve();
}

/** Like above, but with a precomputed rect. Always returns a Promise. */
export function safeFitBoundsRect(
  flow: ReactFlowInstance | undefined,
  rect: Rect | null | undefined,
  opts: { duration?: number; padding?: number } = {}
): Promise<void> {
  const ok =
    !!flow &&
    !!rect &&
    Number.isFinite(rect.x) &&
    Number.isFinite(rect.y) &&
    Number.isFinite(rect.width) &&
    Number.isFinite(rect.height);

  return ok ? flow.fitBounds(rect, opts) : Promise.resolve();
}
