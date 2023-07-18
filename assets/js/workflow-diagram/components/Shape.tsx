import React from 'react';

type ShapeProps = {
  width: number;
  height: number;
  strokeWidth: number;
  styles: any;
  shape?: 'circle' | 'rect';
};

const Circle = ({ width, height, styles, strokeWidth }: ShapeProps) => (
  <ellipse
    // Note we have to offset the x/y position by the stroke width or the stroke will clip outside the canvas
    cx={strokeWidth + width / 2}
    cy={strokeWidth + height / 2}
    rx={width / 2}
    ry={height / 2}
    strokeWidth={strokeWidth}
    {...styles}
  />
);

const Rect = ({ width, height, styles, strokeWidth }: ShapeProps) => (
  <rect
    // Note we have to offset the x/y position by the stroke width or the stroke will clip outside the canvas
    x={strokeWidth}
    y={strokeWidth}
    rx={16}
    width={width}
    height={height}
    strokeWidth={strokeWidth}
    {...styles}
  />
);

const Shape = ({ shape, width, height, strokeWidth, styles }: ShapeProps) => {
  if (shape === 'circle') {
    return (
      <Circle
        width={width}
        height={height}
        styles={styles}
        strokeWidth={strokeWidth}
      />
    );
  } else {
    return (
      <Rect
        width={width}
        height={height}
        styles={styles}
        strokeWidth={strokeWidth}
      />
    );
  }
};

export default Shape;
