import React, { memo } from "react";

const EmptyWorkflowNode = () => <div></div>;

EmptyWorkflowNode.displayName = "WorkflowNode";

export default memo(EmptyWorkflowNode);
