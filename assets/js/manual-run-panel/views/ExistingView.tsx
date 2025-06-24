import React, { type KeyboardEvent } from 'react';
import {
  DataclipTypeNames,
  DataclipTypes,
  FilterTypes,
  type Dataclip,
  type SetDates,
} from '../types';
import useOutsideClick from '#/hooks/useOutsideClick';
import Pill from '../Pill';
import DataclipTypePill from '../DataclipTypePill';
import {
  CalendarDaysIcon,
  ClockIcon,
  MagnifyingGlassIcon,
  RectangleGroupIcon,
  XMarkIcon,
} from '@heroicons/react/24/outline';
import formatDate from '#/utils/formatDate';
import truncateUid from '#/utils/truncateUID';

interface ExistingViewProps {
  dataclips: Dataclip[];
  query: string;
  setQuery: (v: string) => void;
  setSelected: (v: Dataclip) => void;
  filters: Record<string, string | undefined>;
  selectedClipType: string;
  setSelectedClipType: (v: string) => void;
  clearFilter: (v: FilterTypes) => void;
  selectedDates: { before: string; after: string };
  setSelectedDates: SetDates;
  onSubmit: () => void;
  currentRunDataclip?: Dataclip | null;
  nextCronRunId?: string | null;
}

const ExistingView: React.FC<ExistingViewProps> = ({
  dataclips,
  query,
  setQuery,
  setSelected,
  filters,
  selectedClipType,
  setSelectedClipType,
  clearFilter,
  selectedDates,
  setSelectedDates,
  onSubmit,
  currentRunDataclip,
  nextCronRunId,
}) => {
  const [typesOpen, setTypesOpen] = React.useState(false);
  const [dateOpen, setDateOpen] = React.useState(false);
  const calendarRef = useOutsideClick<HTMLDivElement>(() => {
    setDateOpen(false);
  });
  const typesRef = useOutsideClick<HTMLUListElement>(() => {
    setTypesOpen(false);
  });

  const pills = Object.entries(filters)
    .filter(([_, value]) => value !== undefined)
    .map(([key, value]) => (
      <Pill
        onClose={() => {
          clearFilter(key as FilterTypes);
        }}
      >
        {key}:{' '}
        {(key as FilterTypes) === FilterTypes.DATACLIP_TYPE
          ? DataclipTypeNames[value!]
          : value}{' '}
      </Pill>
    ));

  const keyDownHandler = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') onSubmit();
  };

  return (
    <>
      <div className="mt-2 flex flex-col gap-3">
        <div>
          <div className="flex gap-1">
            <div className="relative rounded-md shadow-xs flex grow">
              <input
                onKeyDown={keyDownHandler}
                value={query}
                onChange={e => {
                  setQuery(e.target.value);
                }}
                type="text"
                className="focus:outline focus:outline-2 focus:-outline-offset-2 focus:ring-0  disabled:cursor-not-allowed disabled:bg-gray-50 disabled:text-gray-500 border-slate-300 focus:border-slate-400 focus:outline-indigo-600 block w-full rounded-md border-0 py-1.5 pl-10 pr-20 text-gray-900 ring-1 ring-inset ring-gray-300 placeholder:text-gray-400  focus:ring-inset focus:ring-indigo-600 sm:text-sm sm:leading-6"
                placeholder="Search by UUID (starts with)"
              />
              <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                <MagnifyingGlassIcon className="h-5 w-5 text-gray-400" />
              </div>
              {query.trim() ? (
                <div
                  onClick={() => {
                    setQuery('');
                  }}
                  className="absolute inset-y-0 right-0 flex items-center pr-3 cursor-pointer"
                >
                  <XMarkIcon className="h-5 w-5 text-gray-400" />
                </div>
              ) : null}
            </div>
            <div className="relative inline-block">
              <button
                onClick={() => {
                  setDateOpen(p => !p);
                }}
                className="border rounded-md px-3 py-1 h-full flex justify-center items-center hover:bg-slate-100 hover:border-slate-300"
              >
                <CalendarDaysIcon className="w-6 h-6 text-slate-700" />
              </button>
              <div
                ref={calendarRef}
                className={`absolute right-0 ml-1.5 z-10 mt-2 origin-top-left rounded-md bg-white shadow-lg ring-1 ring-black/5 focus:outline-none min-w-[260px] ${
                  dateOpen ? '' : 'hidden'
                } `}
              >
                <div className="py-3" role="none">
                  <div className="px-4 py-1 text-gray-500 text-sm">
                    Filter by Date Created
                  </div>
                  <div className="px-4 py-1 text-gray-700 text-sm">
                    <label htmlFor="created-after">Created After</label>
                    <input
                      value={selectedDates.after}
                      id="created-after"
                      onChange={e => {
                        setSelectedDates(p => ({
                          after: e.target.value,
                          before: p.before,
                        }));
                      }}
                      className="focus:outline focus:outline-2 focus:outline-offset-1 block w-full rounded-lg border-slate-300 text-slate-900 focus:ring-0 sm:text-sm sm:leading-6"
                      type="datetime-local"
                    />
                  </div>
                  <div className="px-4 py-1 text-gray-700 text-sm">
                    <label htmlFor="created-before">Created Before</label>
                    <input
                      value={selectedDates.before}
                      id="created-before"
                      onChange={e => {
                        setSelectedDates(p => ({
                          after: p.after,
                          before: e.target.value,
                        }));
                      }}
                      className="focus:outline focus:outline-2 focus:outline-offset-1 block w-full rounded-lg border-slate-300 text-slate-900 focus:ring-0 sm:text-sm sm:leading-6"
                      type="datetime-local"
                    />
                  </div>
                </div>
              </div>
            </div>
            <div className="relative inline-block">
              <button
                onClick={() => {
                  setTypesOpen(p => !p);
                }}
                className="border rounded-md px-3 py-1 h-full flex justify-center items-center hover:bg-slate-100 hover:border-slate-300"
              >
                <RectangleGroupIcon className="w-6 h-6 text-slate-700" />
              </button>
              <ul
                ref={typesRef}
                className={`absolute z-10 mt-2 bg-white ring-1 ring-black/5 focus:outline-none rounded-md shadow-lg right-0 w-auto overflow-hidden ${
                  typesOpen ? '' : 'hidden'
                } `}
              >
                {DataclipTypes.map(type => {
                  return (
                    <li
                      key={type}
                      onClick={() => {
                        setSelectedClipType(
                          type === selectedClipType ? '' : type
                        );
                      }}
                      className={`px-3 py-2 hover:bg-slate-100 cursor-pointer text-nowrap flex items-center gap-2 text-slate-700 ${
                        type === selectedClipType
                          ? 'bg-blue-200 text-blue-700'
                          : ''
                      }`}
                    >
                      <span
                        className={`hero-check size-4 text-gray-400 ${
                          type !== selectedClipType ? 'invisible' : ''
                        }`}
                      />
                      <span className="text-sm">{DataclipTypeNames[type]}</span>
                    </li>
                  );
                })}
              </ul>
            </div>
            <div className="relative inline-block">
              <button
                onClick={() => {
                  onSubmit();
                }}
                // TODO: This should come from app.css (lib/lightning_web/components/new_inputs.ex button_base_classes)
                className="rounded-md text-sm font-semibold shadow-xs phx-submit-loading:opacity-75 bg-primary-600 hover:bg-primary-500 text-white disabled:bg-primary-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600 px-3 py-2"
              >
                Search
              </button>
            </div>
          </div>
          <div className="flex gap-1 mt-2">{pills}</div>
        </div>
        {dataclips.length ? (
          dataclips.map(clip => {
            const isCurrent =
              currentRunDataclip && clip.id === currentRunDataclip.id;
            const isNextCronRun = nextCronRunId && clip.id === nextCronRunId;
            return (
              <div
                key={clip.id}
                onClick={() => {
                  setSelected(clip);
                }}
                className="flex items-center justify-between border rounded-md px-3 py-2 cursor-pointer hover:bg-slate-100 hover:border-primary-600 group"
              >
                <div className="flex gap-2 items-center text-sm">
                  {isCurrent ? (
                    <span
                      className="hero-star-solid size-4 text-primary-400 group-hover:text-primary-600"
                      title="Current dataclip for this step"
                    />
                  ) : isNextCronRun ? (
                    <ClockIcon
                      className="size-4 text-orange-400 group-hover:text-orange-600"
                      title="Next state that will be used for cron execution"
                    />
                  ) : (
                    <span className="hero-document-text align-middle size-4 group-hover:text-primary-600" />
                  )}
                  <span className="font-mono leading-none align-middle relative top-[1px]">
                    {truncateUid(clip.id)}
                  </span>
                  <span className="align-middle">
                    <DataclipTypePill type={clip.type} size="small" />
                  </span>
                </div>
                <div className="text-xs truncate ml-2">
                  {formatDate(new Date(clip.updated_at))}
                </div>
              </div>
            );
          })
        ) : (
          <div className="text-center text-sm">
            No dataclips match the filter.
          </div>
        )}
        {dataclips.length ? (
          <div className="text-center text-sm text-gray-600">
            Search results are limited to the 10 most recent matches for this
            step.
          </div>
        ) : null}
      </div>
    </>
  );
};

export default ExistingView;
