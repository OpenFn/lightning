import React, { memo, useState } from 'react';
import { Handle, Position, NodeProps } from 'reactflow';
import Node from './Node';
import PlusButton from './PlusButton';
import getAdaptorName from '../util/get-adaptor-name';

type NodeData = any;

const JobNode = ({
  targetPosition = Position.Top,
  sourcePosition = Position.Bottom,
  ...props
}: NodeProps<NodeData>) => {
  const toolbar = () => props.data?.allowPlaceholder && <PlusButton />
  console.log(props.data)

  const adaptor = getAdaptorName(props.data?.adaptor)
  return (<Node
    {...props}
    label={props.data?.name}
    sublabel={adaptor}
    targetPosition={targetPosition}
    sourcePosition={sourcePosition}
    allowSource
    toolbar={toolbar}
  />)
 
};

JobNode.displayName = 'JobNode';

export default memo(JobNode);
