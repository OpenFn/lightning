import { LinkIcon } from '@heroicons/react/24/outline';
import { Handle, Position } from '@xyflow/react';
import type { PropsWithChildren } from 'react';

interface PathButtonProps {
  id: string;
}

const PathButton: React.FC<PropsWithChildren<PathButtonProps>> = props => {
  return (
    <Handle
      id={props.id}
      position={Position.Bottom}
      type="source"
      style={{
        position: 'relative',
        height: 24,
        width: 'auto',

        // These values come from tailwind but have to be set on styles to override reactflow stuff
        borderRadius: '0.5rem',
        borderWidth: '0',

        // override react flow stuff
        transform: 'translate(0,0)',
        left: 'auto',
        top: 'auto',
        cursor: 'pointer',
      }}
      className="transition duration-150 ease-in-out pointer-events-auto rounded-lg
      !bg-indigo-600 hover:!bg-indigo-500 py-1 px-2 text-[0.8125rem] font-semibold leading-5 text-white
      flex items-center justify-center ml-1"
    >
      {props.children}
    </Handle>
  );
};

export default PathButton;
