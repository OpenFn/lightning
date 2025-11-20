import { useCallback, useEffect, useRef, useState } from 'react';

/**
 * Custom hook to calculate and track the overlap between an Inspector panel
 * and a diagram area. Returns the overlap width for positioning components.
 */
export function useInspectorOverlap(
  inspectorId: string | undefined,
  diagramRef: React.RefObject<HTMLDivElement | null>
) {
  const [overlapWidth, setOverlapWidth] = useState(0);
  const inspectorRef = useRef<HTMLElement | null>(null);

  // Calculate Inspector overlap with diagram area
  const calculateOverlap = useCallback(() => {
    if (!inspectorRef.current || !diagramRef.current) {
      return 0;
    }

    const inspectorRect = inspectorRef.current.getBoundingClientRect();
    const diagramRect = diagramRef.current.getBoundingClientRect();

    // Check if Inspector overlaps with the diagram area
    const rightEdgeOfDiagram = diagramRect.right;
    const leftEdgeOfInspector = inspectorRect.left;

    // If Inspector starts before diagram ends, there's overlap
    if (leftEdgeOfInspector < rightEdgeOfDiagram) {
      const overlap = rightEdgeOfDiagram - leftEdgeOfInspector;
      // Cap the overlap to the Inspector's actual width
      return Math.min(overlap, inspectorRect.width);
    }

    return 0;
  }, [diagramRef]);

  // Effect to handle Inspector panel overlap changes
  useEffect(() => {
    if (!inspectorId) {
      setOverlapWidth(0);
      inspectorRef.current = null;
      return;
    }

    // Update ref with current element
    inspectorRef.current = document.getElementById(inspectorId);

    const updateOverlap = () => {
      const overlap = calculateOverlap();
      setOverlapWidth(overlap);
    };

    // Initial calculation
    updateOverlap();

    // Use ResizeObserver to detect changes in both Inspector and diagram
    let inspectorObserver: ResizeObserver | null = null;
    let diagramObserver: ResizeObserver | null = null;

    const inspector = inspectorRef.current;
    const diagram = diagramRef.current;

    if (inspector && diagram) {
      inspectorObserver = new ResizeObserver(() => {
        // Small delay to ensure DOM updates are complete
        setTimeout(updateOverlap, 10);
      });

      diagramObserver = new ResizeObserver(() => {
        setTimeout(updateOverlap, 10);
      });

      inspectorObserver.observe(inspector);
      diagramObserver.observe(diagram);
    }

    // Also listen for Inspector position changes (transform updates)
    let animationFrame: number;
    const checkForChanges = () => {
      updateOverlap();
      animationFrame = requestAnimationFrame(checkForChanges);
    };
    animationFrame = requestAnimationFrame(checkForChanges);

    return () => {
      if (inspectorObserver) inspectorObserver.disconnect();
      if (diagramObserver) diagramObserver.disconnect();
      if (animationFrame) cancelAnimationFrame(animationFrame);
    };
  }, [inspectorId, calculateOverlap, diagramRef]);

  return overlapWidth;
}
