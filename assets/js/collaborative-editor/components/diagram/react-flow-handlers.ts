import type { Node, OnNodeDrag } from '@xyflow/react';

type DragParams = [...Parameters<OnNodeDrag<Node>>, isClick: boolean];
type DragCallback = (...params: DragParams) => void;

interface HandlerOptions {
  dragThreshold: number;
}

function flowHandlers(options: HandlerOptions = { dragThreshold: 1 }) {
  let dragStartPos: { x: number; y: number } | undefined;

  const ondragstart: (cb?: OnNodeDrag<Node>) => OnNodeDrag<Node> =
    cb => (event, node) => {
      dragStartPos = { x: event.clientX, y: event.clientY };
      cb?.(event, node, [node]);
    };

  const ondragstop: (cb?: DragCallback) => OnNodeDrag<Node> =
    cb => (event, node) => {
      let isClick = false;
      if (dragStartPos) {
        const distance = Math.sqrt(
          Math.pow(event.clientX - dragStartPos.x, 2) +
            Math.pow(event.clientY - dragStartPos.y, 2)
        );
        if (distance < options.dragThreshold) isClick = true;
      }
      dragStartPos = undefined;
      cb?.(event, node, [node], isClick);
    };
  return { ondragstart, ondragstop };
}

export default flowHandlers;
