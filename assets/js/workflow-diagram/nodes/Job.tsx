import { Position, type NodeProps } from '@xyflow/react';
import { memo } from 'react';

import PathButton from '../components/PathButton';
import useAdaptorIcons, { type AdaptorIconData } from '../useAdaptorIcons';
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
    const iconData = adaptorIconsData?.[adaptor];
    if (iconData?.square) {
      const srcPath = iconData.square;
      return <img src={srcPath} alt={adaptor} />;
    } else {
      return adaptor;
    }
  } catch {
    return adaptor;
  }
}

export default memo(JobNode);
