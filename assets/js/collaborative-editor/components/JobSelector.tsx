import {
  Listbox,
  ListboxButton,
  ListboxOption,
  ListboxOptions,
} from '@headlessui/react';
import { useMemo } from 'react';

import type { Job } from '../types/job';

interface JobSelectorProps {
  currentJob: Job;
  jobs: Job[];
  onChange: (job: Job) => void;
}

/**
 * JobSelector - Breadcrumb-styled dropdown for job selection
 *
 * Renders as the final breadcrumb in IDE view, allowing users to
 * switch between jobs without returning to canvas.
 *
 * Uses Headless UI Listbox with Tailwind "simple custom" styling.
 */
export function JobSelector({ currentJob, jobs, onChange }: JobSelectorProps) {
  return (
    <Listbox value={currentJob} onChange={onChange}>
      <div className="relative">
        <ListboxButton className="flex items-center font-medium text-sm text-gray-500 hover:text-gray-700 cursor-pointer">
          <span>{currentJob.name}</span>
          <span className="hero-chevron-up-down w-4 h-4 ml-1 flex-shrink-0" />
        </ListboxButton>
        <ListboxOptions
          transition
          anchor="bottom start"
          className="z-[100] mt-1 max-h-60 w-56 overflow-auto rounded-md bg-white py-1 text-sm shadow-lg outline-1 outline-black/5 data-leave:transition data-leave:duration-100 data-leave:ease-in data-closed:data-leave:opacity-0"
        >
          {jobs.map(job => (
            <ListboxOption
              key={job.id}
              value={job}
              className="group relative cursor-default py-2 pr-9 pl-3 text-gray-900 select-none data-focus:bg-indigo-600 data-focus:text-white data-focus:outline-hidden"
            >
              <span className="block truncate font-normal group-data-selected:font-semibold">
                {job.name}
              </span>
              <span className="absolute inset-y-0 right-0 flex items-center pr-4 text-indigo-600 group-not-data-selected:hidden group-data-focus:text-white">
                <span className="hero-check w-5 h-5" />
              </span>
            </ListboxOption>
          ))}
        </ListboxOptions>
      </div>
    </Listbox>
  );
}
