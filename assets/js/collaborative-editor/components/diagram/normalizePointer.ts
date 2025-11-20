import type { XYPosition, Transform } from '@xyflow/react';

// functions for normalizing pointer positions based on zoom and pan.
// I was fustrated by the built-in screentoflowposition and its inverse provided by reactflow.
// credit: https://github.com/xyflow/xyflow/issues/3771#issuecomment-1880103788

export const denormalizePointerPosition = (
  { x, y }: XYPosition,
  [tx, ty, tScale]: Transform
): XYPosition => {
  const position: XYPosition = {
    x: x * tScale + tx,
    y: y * tScale + ty,
  };

  return position;
};

export const normalizePointerPosition = (
  { x, y }: XYPosition,
  [tx, ty, tScale]: Transform
): XYPosition => {
  const position: XYPosition = {
    x: (x - tx) / tScale,
    y: (y - ty) / tScale,
  };

  return position;
};
