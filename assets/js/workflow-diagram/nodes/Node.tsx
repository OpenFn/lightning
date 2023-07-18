import React, { memo } from 'react';
import { Handle, NodeProps } from 'reactflow';
import Shape from './shapes';
import { nodeIconStyles, nodeLabelStyles } from '../styles';

type NodeData = any;

type BaseNodeProps = NodeProps<NodeData> & {
  shape?: 'circle' | 'rect';
  icon?: string;
  label?: string;
  sublabel?: string;
  toolbar?: any;
};

const Label = ({ children }: React.PropsWithChildren) => {
  if (children && (children as any).length) {
    return <p className="line-clamp-2 align-left text-m">{children}</p>;
  }
  return null;
};

const SubLabel = ({ children }: React.PropsWithChildren) => {
  if (children && (children as any).length) {
    return (
      <p className="line-clamp-2 align-left text-sm text-slate-500">
        {children}
      </p>
    );
  }
  return null;
};

const Node = ({
  // standard  react flow stuff
  isConnectable,
  selected,
  targetPosition,
  sourcePosition,

  // custom stuff
  toolbar,
  shape,
  label, // main label which appears to the right
  sublabel, // A smaller label to the right
  icon, // displayed inside the SVG shape
}: BaseNodeProps) => {
  const { width, height, anchorx, strokeWidth, style } =
    nodeIconStyles(selected);

  return (
    <div className="group">
      <div className="flex flex-row">
        <div>
          {targetPosition && (
            <Handle
              type="target"
              isConnectable={isConnectable}
              position={targetPosition}
              style={{
                visibility: 'hidden',
                height: 0,
                top: 0,
                left: strokeWidth + anchorx,
              }}
            />
          )}
          <svg style={{ maxWidth: '110px', maxHeight: '110px' }}>
            <Shape
              shape={shape}
              width={width}
              height={height}
              strokeWidth={strokeWidth}
              styles={style}
            />
          </svg>
          {icon && (
            <div
              style={{
                position: 'absolute',
                // Position is half of the difference of the actual width, offset for stroke
                left: 0.1 * width + strokeWidth,
                top: 0.1 * height + strokeWidth,
                height: `${0.8 * height}px`,
                width: `${0.8 * width}px`,
                ...nodeLabelStyles(selected),
              }}
            >
              {typeof icon === 'string' ? (
                <div className="font-bold">{icon}</div>
              ) : (
                icon
              )}
            </div>
          )}
        </div>
        {sourcePosition && (
          <Handle
            type="source"
            isConnectable={isConnectable}
            position={sourcePosition}
            style={{
              visibility: 'hidden',
              height: 0,
              top: height,
              left: strokeWidth + anchorx,
            }}
          />
        )}
        <div className="flex flex-col flex-1 justify-center ml-2">
          <Label>{label}</Label>
          <SubLabel>{sublabel}</SubLabel>
        </div>
      </div>
      {toolbar && (
        <div
          style={{ width: `${width}px`, marginTop: '-14px' }}
          className="flex flex-col items-center
                    opacity-0  group-hover:opacity-100
                    transition duration-150 ease-in-out"
        >
          {toolbar()}
        </div>
      )}
    </div>
  );
};

Node.displayName = 'Node';

export default memo(Node);
