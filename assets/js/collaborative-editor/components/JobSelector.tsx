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
  const sortedJobs = useMemo(() => {
    return [...jobs].sort((a, b) => a.name.localeCompare(b.name));
  }, [jobs]);

  return (
    <Listbox value={currentJob} onChange={onChange}>
      <div className="relative">
        <ListboxButton className="inline-flex items-center gap-x-1 text-sm font-semibold text-gray-900 cursor-pointer hover:text-gray-700">
          <span className="truncate">{currentJob.name}</span>
          <span
            className="hero-chevron-down h-5 w-5 text-gray-400"
            aria-hidden="true"
          />
        </ListboxButton>
        <ListboxOptions
          transition
          anchor="bottom start"
          className="z-[100] mt-1 max-h-60 w-56 overflow-auto rounded-md bg-white py-1 shadow-lg ring-1 ring-inset ring-gray-300 focus:outline-none sm:text-sm data-leave:transition data-leave:duration-100 data-leave:ease-in data-closed:data-leave:opacity-0"
        >
          {sortedJobs.map(job => (
            <ListboxOption
              key={job.id}
              value={job}
              className="group relative cursor-pointer select-none py-2 pl-3 pr-9 text-sm data-focus:bg-indigo-600 data-focus:text-white"
            >
              <span className="flex items-center">
                <span className="block truncate font-normal group-data-selected:font-semibold flex-grow mr-6">
                  {job.name}
                </span>
              </span>
              <span className="absolute inset-y-0 right-0 flex items-center pr-3 group-not-data-selected:hidden">
                <span className="hero-check w-5 h-5 text-indigo-600 group-data-focus:text-white" />
              </span>
            </ListboxOption>
          ))}
        </ListboxOptions>
      </div>
    </Listbox>
  );
}
