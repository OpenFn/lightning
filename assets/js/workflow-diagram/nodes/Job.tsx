import { memo } from 'react';
import { Position, type NodeProps } from '@xyflow/react';
import Node from './Node';
import PathButton from '../components/PathButton';
import getAdaptorName from '../util/get-adaptor-name';
import useAdaptorIcons, { type AdaptorIconData } from '../useAdaptorIcons';

type NodeData = any;

const JobNode = ({
  targetPosition = Position.Top,
  sourcePosition = Position.Bottom,
  ...props
}: NodeProps<NodeData>) => {
  const toolbar = () => [
    props.data?.allowPlaceholder && [
      <PathButton key="+path" id='node-connector' >
        <span className='hero-link h-4 w-4 pointer-events-none'></span>
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
