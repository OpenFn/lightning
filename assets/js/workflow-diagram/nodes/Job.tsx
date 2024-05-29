import React, { memo, useEffect, useState } from 'react';
import { Position, NodeProps, Handle } from 'reactflow';
import Node from './Node';
import PlusButton from '../components/PlusButton';
import getAdaptorName from '../util/get-adaptor-name';
import useAdaptorIcons, { AdaptorIconData } from '../useAdaptorIcons';

type NodeData = any;

const JobNode = ({
  targetPosition = Position.Top,
  sourcePosition = Position.Bottom,
  ...props
}: NodeProps<NodeData>) => {
  const toolbar = () => [
    props.data?.allowPlaceholder && <PlusButton />,
    <Handle
      type="source"
      style={{
        position: 'static',
        height: 20,
        width: 'auto',
        background: 'transparent',
        borderRadius: 0,
      }}
    >
      LINK
    </Handle>,
  ];

  const adaptorIconsData = useAdaptorIcons();

  const adaptor = getAdaptorName(props.data?.adaptor);
  const icon = getAdaptorIcon(adaptor, adaptorIconsData);

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

function getAdaptorIcon(
  adaptor: string,
  adaptorIconsData: AdaptorIconData | null
) {
  try {
    if (
      adaptorIconsData &&
      adaptor in adaptorIconsData &&
      adaptorIconsData[adaptor]?.square
    ) {
      const srcPath = adaptorIconsData[adaptor].square;
      return <img src={srcPath} alt={adaptor} />;
    } else {
      return adaptor;
    }
  } catch (e) {
    return adaptor;
  }
}

export default memo(JobNode);
