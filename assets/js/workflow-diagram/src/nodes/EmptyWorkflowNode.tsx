import React, { memo } from "react";
import type { NodeProps } from "react-flow-renderer";

const EmptyWorkflowNode = ({dragging = true}: NodeProps) => <div draggable={dragging} className="drag"></div>;

EmptyWorkflowNode.displayName = "WorkflowNode";

export default memo(EmptyWorkflowNode);
