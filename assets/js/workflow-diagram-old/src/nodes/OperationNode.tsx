import React, { memo } from "react";

import { Handle, Position } from "react-flow-renderer";
import type { NodeProps } from "react-flow-renderer";

// background:#fff
// border:1px solid #1a192b
// border-radius:3px
// color:#222
// font-size:12px
// padding:10px
// text-align:center
// width:150px

const OperationNode = ({
  data,
  isConnectable,
  targetPosition = Position.Top,
  sourcePosition = Position.Bottom,
}: NodeProps) => {
  return (
    <div
      className="bg-white rounded-md
                   ring-1 ring-black ring-opacity-5 
                   text-xs p-2 text-center h-full"
    >
      <Handle
        type="target"
        position={targetPosition}
        isConnectable={isConnectable}
        style={{ border: "none", height: 0, top: 0 }}
      />

      <div className={`flex h-full ${data.hasChildren ? "" : "items-center"}`}>
        <div className="flex-auto">{data?.label}</div>
      </div>
      <Handle
        type="source"
        position={sourcePosition}
        isConnectable={isConnectable}
        style={{ border: "none", height: 0, top: 0 }}
      />
    </div>
  );
};

OperationNode.displayName = "OperationNode";

export default memo(OperationNode);
