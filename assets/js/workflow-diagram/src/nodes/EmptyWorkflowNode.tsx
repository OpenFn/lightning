import React, { memo } from "react";

const EmptyWorkflowNode = () => <div className="h-full cursor-default"></div>;

EmptyWorkflowNode.displayName = "WorkflowNode";

export default memo(EmptyWorkflowNode);
