import React, { memo } from 'react';
import { Position, NodeProps } from 'reactflow';
import Node from './Node';
import PlusButton from '../components/PlusButton';
import getAdaptorName from '../util/get-adaptor-name';
import * as icons from '../components/adaptor-icons';

type NodeData = any;

const JobNode = ({
  targetPosition = Position.Top,
  sourcePosition = Position.Bottom,
  ...props
}: NodeProps<NodeData>) => {
  const toolbar = () => props.data?.allowPlaceholder && <PlusButton />;

  const adaptor = getAdaptorName(props.data?.adaptor);
  const icon = getAdaptorIcon(adaptor);
  return (
    <Node
      {...props}
      label={props.data?.name}
      icon={icon}
      sublabel={adaptor}
      targetPosition={targetPosition}
      sourcePosition={sourcePosition}
      allowSource
      toolbar={toolbar}
      errors={props.data?.errors}
    />
  );
};

JobNode.displayName = 'JobNode';

export default memo(JobNode);

function getAdaptorIcon(adaptor: string) {
  return <img src={`/assets/images/adaptors/${adaptor}-square.png`} />;
}
