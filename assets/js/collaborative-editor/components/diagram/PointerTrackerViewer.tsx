import { useViewport } from '@xyflow/react';
import { useCallback, useEffect } from 'react';

import { useAwarenessCommands } from '#/collaborative-editor/hooks/useAwareness';

import { normalizePointerPosition } from './normalizePointer';
import { RemoteCursors } from './RemoteCursor';

export function PointerTrackerViewer({
  containerEl: container,
}: {
  containerEl: HTMLDivElement;
}) {
  const { updateLocalCursor } = useAwarenessCommands();
  const { x: tx, y: ty, zoom: tzoom } = useViewport();

  const handleMouseMove = useCallback(
    (e: MouseEvent) => {
      if (!container) return;
      const bounds = container.getBoundingClientRect();

      const clientXRelativeToPane = e.clientX - bounds.left;
      const clientYRelativeToPane = e.clientY - bounds.top;

      const normPosition = normalizePointerPosition(
        {
          x: clientXRelativeToPane,
          y: clientYRelativeToPane,
        },
        [tx, ty, tzoom]
      );

      updateLocalCursor({ x: normPosition.x, y: normPosition.y });
    },
    [updateLocalCursor, container, tx, ty, tzoom]
  );

  const handleMouseLeave = useCallback(() => {
    updateLocalCursor(null);
  }, [updateLocalCursor]);

  useEffect(() => {
    if (!container) return;

    container.addEventListener('mousemove', handleMouseMove);
    container.addEventListener('mouseleave', handleMouseLeave);

    return () => {
      container.removeEventListener('mousemove', handleMouseMove);
      container.removeEventListener('mouseleave', handleMouseLeave);
    };
  }, [handleMouseMove, handleMouseLeave, container]);

  return <RemoteCursors />;
}
