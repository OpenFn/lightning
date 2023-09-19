import React from 'react';

function PlusButton() {
  return (
    <button
      name="add-node"
      className="transition duration-150 ease-in-out pointer-events-auto rounded-full
               bg-indigo-600 py-1 px-4 text-[0.8125rem] font-semibold leading-5 text-white hover:bg-indigo-500"
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 24 24"
        fill="currentColor"
        className="w-4 h-4"
      >
        <path
          fillRule="evenodd"
          d="M12 5.25a.75.75 0 01.75.75v5.25H18a.75.75 0 010 1.5h-5.25V18a.75.75 0 01-1.5 0v-5.25H6a.75.75 0 010-1.5h5.25V6a.75.75 0 01.75-.75z"
          clipRule="evenodd"
        />
      </svg>
    </button>
  );
}

export default PlusButton;
