import React from "react";
import { DataclipTypeNames, DataclipTypes, FilterTypes, type Dataclip, type SetDates } from "../types";
import useOutsideClick from "#/hooks/useOutsideClick";
import Pill from "../Pill";
import { CalendarDaysIcon, CheckIcon, DocumentTextIcon, MagnifyingGlassIcon, RectangleGroupIcon, XMarkIcon } from "@heroicons/react/24/outline";
import formatDate from "#/utils/formatDate";
import truncateUid from "#/utils/truncateUID";

const iconStyle = 'h-4 w-4 text-grey-400';

interface ExistingViewProps {
  dataclips: Dataclip[];
  query: string;
  setQuery: (v: string) => void;
  setSelected: (v: Dataclip) => void;
  filters: Record<string, string>;
  selectedcliptype: string;
  setSelectedclipType: (v: string) => void;
  clearFilter: (v: FilterTypes) => void;
  selectedDates: { before: string; after: string };
  setSelectedDates: SetDates;
}

const ExistingView: React.FC<ExistingViewProps> = ({
  dataclips,
  query,
  setQuery,
  setSelected,
  filters,
  selectedcliptype,
  setSelectedclipType,
  clearFilter,
  selectedDates,
  setSelectedDates,
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
    .map(([key, value]) => (
      <Pill onClose={() => { clearFilter(key as FilterTypes) }}>
        {key}: {(key as FilterTypes) === FilterTypes.DATACLIP_TYPE ? DataclipTypeNames[value] : value}{' '}
      </Pill>
    ));

  return (
    <>
      <div className="flex flex-col gap-3">
        <div>
          <div className="flex gap-2">
            <div className="relative rounded-md shadow-xs flex grow">
              <input
                value={query}
                onChange={e => {
                  setQuery(e.target.value);
                }}
                type="text"
                className="focus:outline focus:outline-2 focus:-outline-offset-2 focus:ring-0  disabled:cursor-not-allowed disabled:bg-gray-50 disabled:text-gray-500 border-slate-300 focus:border-slate-400 focus:outline-indigo-600 block w-full rounded-md border-0 py-1.5 pl-10 pr-20 text-gray-900 ring-1 ring-inset ring-gray-300 placeholder:text-gray-400  focus:ring-inset focus:ring-indigo-600 sm:text-sm sm:leading-6"
                placeholder="Filter inputs"
              />
              <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                <MagnifyingGlassIcon className="h-5 w-5 text-gray-400" />
              </div>
              {
                query.trim() ?
                  <div
                    onClick={() => { setQuery("") }}
                    className="absolute inset-y-0 right-0 flex items-center pr-3 cursor-pointer">
                    <XMarkIcon className="h-5 w-5 text-gray-400" />
                  </div>
                  : null
              }
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
                className={`absolute right-0 ml-1.5 z-10 mt-2 origin-top-left rounded-md bg-white shadow-lg ring-1 ring-black/5 focus:outline-none min-w-[260px] ${dateOpen ? '' : 'hidden'
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
                      type="date"
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
                      type="date"
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
                className={`absolute z-10 mt-2 bg-white ring-1 ring-black/5 focus:outline-none rounded-md shadow-lg right-0 w-auto overflow-hidden ${typesOpen ? '' : 'hidden'
                  } `}
              >
                {DataclipTypes.map(type => {
                  return (
                    <li
                      key={type}
                      onClick={() => {
                        setSelectedclipType(
                          type === selectedcliptype ? '' : type
                        );
                      }}
                      className={`px-4 py-2 hover:bg-slate-100 cursor-pointer text-nowrap flex items-center gap-2 text-base text-slate-700 ${type === selectedcliptype
                        ? 'bg-blue-200 text-blue-700'
                        : ''
                        }`}
                    >
                      {' '}
                      {DataclipTypeNames[type]}{' '}
                      <CheckIcon
                        strokeWidth={3}
                        className={`${iconStyle} ${type !== selectedcliptype ? 'invisible' : ''
                          }`}
                      />{' '}
                    </li>
                  );
                })}
              </ul>
            </div>
          </div>
          <div className="flex gap-1 mt-2">{pills}</div>

        </div>
        {dataclips.length ? (
          dataclips.map(clip => {
            return (
              <div
                onClick={() => {
                  setSelected(clip);
                }}
                className="flex items-center justify-between border rounded-md px-3 py-2 cursor-pointer hover:bg-slate-100 hover:border-primary-600 group"
              >
                <div className="flex gap-1 items-center text-sm">
                  {' '}
                  <DocumentTextIcon
                    className={`${iconStyle} group-hover:scale-110 group-hover:text-primary-600`}
                  />{' '}
                  {truncateUid(clip.id)}{' '}
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
      </div>
    </>
  );
};

export default ExistingView;