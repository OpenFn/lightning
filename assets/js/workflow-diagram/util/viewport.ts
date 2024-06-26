// Given react-flows viewport, which gives use the topleft x/y and
// zoom, and the dimensions of the canvas,
// work out the view bounds
import { Rect, XYPosition, Viewport } from 'reactflow';

// TODO use scale to make the bounds artificially smaller
export const getVisibleRect = (
  viewport: Viewport,
  width: number,
  height: number,
  scale = 1
) => {
  // Invert the zoom so that low zooms INCREASE the bouds size
  const zoom = 1 / viewport.zoom;

  // Also invert the viewport x and y positions
  const x = -viewport.x;
  const y = -viewport.y;

  // Return the projected visible rect
  return {
    x: x * zoom,
    width: width * zoom,
    y: y * zoom,
    height: height * zoom,
  };
};

// This returns true if the point at pos fits anywhere inside rect
export const isPointInRect = (pos: XYPosition, rect: Rect) => {
  return (
    pos.x >= rect.x &&
    pos.x <= rect.x + rect.width &&
    pos.y >= rect.y &&
    pos.y <= rect.y + rect.height
  );
};
