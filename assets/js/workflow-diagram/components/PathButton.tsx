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
        // borderRadius: 0,

        // These values come from tailwind but have to be set on styles to override reactflow stuff
        // backgroundColor: 'rgb(79 70 229)',
        borderRadius: '999px',
        borderWidth: '0',

        // override react flow stuff
        transform: 'translate(0,0)',
        left: 'auto',
        top: 'auto',
        cursor: 'pointer',
      }}
      className="transition duration-150 ease-in-out pointer-events-auto rounded-full
      !bg-indigo-600 hover:!bg-indigo-500 py-1 px-4 text-[0.8125rem] font-semibold leading-5 text-white"
    >
      <LinkIcon className="inline h-4 w-4" style={{ marginTop: '-6px' }} />
    </Handle>
  );
}

export default PathButton;
