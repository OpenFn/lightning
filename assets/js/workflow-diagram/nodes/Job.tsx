import React, { memo, useEffect, useState } from 'react';
import { Position, NodeProps } from 'reactflow';
import Node from './Node';
import PlusButton from '../components/PlusButton';
import getAdaptorName from '../util/get-adaptor-name';

type AdaptorIconData = {
  [adaptor: string]: {
    rectangle: string;
    square: string;
  };
};

const fetchAdaptorIconsData = async (): Promise<AdaptorIconData> => {
  try {
    const response = await fetch('/images/adaptors/adaptor_icons.json');
    if (!response.ok) {
      throw new Error('Network error');
    }

    const data: AdaptorIconData = await response.json();
    return data;
  } catch (error) {
    console.error('Error fetching Adaptor Icons manifest:', error);
    return {};
  }
};

type NodeData = any;

const JobNode = ({
  targetPosition = Position.Top,
  sourcePosition = Position.Bottom,
  ...props
}: NodeProps<NodeData>) => {
  const toolbar = () => props.data?.allowPlaceholder && <PlusButton />;

  const [adaptorIconsData, setAdaptorIconsData] = useState<AdaptorIconData | null>(null);

  useEffect(() => {
    // Fetch and set the adaptorIconsData when the component mounts
    fetchAdaptorIconsData()
      .then((data) => {
        setAdaptorIconsData(data);
      });
  }, []);

  const adaptor = getAdaptorName(props.data?.adaptor);
  const icon = getAdaptorIcon(adaptor, adaptorIconsData);

  return (
    <Node
      {...props}
      label={props.data?.name}
      primaryIcon={icon}
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

function getAdaptorIcon(adaptor: string, adaptorIconsData: AdaptorIconData | null) {
  try {
    if (adaptorIconsData && adaptor in adaptorIconsData && adaptorIconsData[adaptor]?.square) {
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
