import React from 'react';

function PlusButton() {
  return (
    <button
      id="plusButton"
      className="transition duration-150 ease-in-out pointer-events-auto rounded-full
               bg-indigo-600 py-1 px-4 text-[0.8125rem] font-semibold leading-5 text-white hover:bg-indigo-500"
    >
      <svg
        id="plusIcon"
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
        strokeWidth="1.5"
        stroke="currentColor"
        className="w-3 h-3"
      >
        <path strokeLinecap="round" strokeLinejoin="round" d="M12 6v12m6-6H6" />
      </svg>
    </button>
  );
}

export default PlusButton;