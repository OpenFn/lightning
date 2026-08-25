import { Position, type NodeProps } from '@xyflow/react';
import { memo } from 'react';

import { useAdaptorIconUrl } from '#/collaborative-editor/hooks/useAdaptors';

import PathButton from '../components/PathButton';
import getAdaptorName from '../util/get-adaptor-name';

import Node from './Node';

type NodeData = any;

const JobNode = ({
  targetPosition = Position.Top,
  sourcePosition = Position.Bottom,
  ...props
}: NodeProps<NodeData>) => {
  const toolbar = () => [
    props.data?.allowPlaceholder && [
      <PathButton key="+path" id="node-connector">
        <span className="hero-plus h-4 w-4 pointer-events-none"></span>
      </PathButton>,
    ],
  ];

  const adaptor = getAdaptorName(props.data?.adaptor);
  const iconUrl = useAdaptorIconUrl(props.data?.adaptor);
  const icon = iconUrl ? <img src={iconUrl} alt={adaptor} /> : adaptor;

  return (
    <Node
      {...props}
      label={props.data?.name}
      primaryIcon={icon}
      sublabel={adaptor}
      isConnectable={true}
      targetPosition={targetPosition}
      sourcePosition={sourcePosition}
      // allowSource
      toolbar={toolbar}
      errors={props.data?.errors}
    />
  );
};

JobNode.displayName = 'JobNode';

export default memo(JobNode);
