import { useViewport } from '@xyflow/react';
import { useCallback, useEffect, useMemo } from 'react';

import { useAwarenessCommands } from '#/collaborative-editor/hooks/useAwareness';
import throttle from '#/collaborative-editor/utils/throttle';

import { normalizePointerPosition } from './normalizePointer';
import { RemoteCursors } from './RemoteCursor';

const CURSOR_THROTTLE_MS = 50;

export function PointerTrackerViewer({
  containerEl: container,
}: {
  containerEl: HTMLDivElement;
}) {
  const { updateLocalCursor } = useAwarenessCommands();
  const { x: tx, y: ty, zoom: tzoom } = useViewport();

  // Throttle cursor updates to reduce server load (~20 updates/sec)
  const throttledUpdateCursor = useMemo(
    () => throttle(updateLocalCursor, CURSOR_THROTTLE_MS),
    [updateLocalCursor]
  );

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

      throttledUpdateCursor({ x: normPosition.x, y: normPosition.y });
    },
    [throttledUpdateCursor, container, tx, ty, tzoom]
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
