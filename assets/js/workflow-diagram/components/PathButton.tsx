import React from 'react';
import { Handle } from 'reactflow';
import { LinkIcon } from '@heroicons/react/24/outline';

function PathButton() {
  return (
    <Handle
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
      !bg-indigo-600 hover:!bg-indigo-500 py-1 px-2 text-[0.8125rem] font-semibold leading-5 text-white"
    >
      <LinkIcon
        className="inline h-4 w-4"
        style={{ marginTop: '-6px', pointerEvents: 'none' }}
      />
    </Handle>
  );
}

export default PathButton;
