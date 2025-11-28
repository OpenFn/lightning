import { DocumentTextIcon, XMarkIcon } from '@heroicons/react/24/outline';
import { ClockIcon } from '@heroicons/react/24/solid';
import React from 'react';

import { DataclipViewer } from '../../react/components/DataclipViewer';
import formatDate from '../../utils/formatDate';
import DataclipTypePill from '../DataclipTypePill';
import Pill from '../Badge';
import type { Dataclip } from '../types';

interface SelectedClipViewProps {
  dataclip: Dataclip;
  onUnselect: () => void;
  isNextCronRun?: boolean;
  canEditDataclip?: boolean;
  onNameChange: (
    dataclipId: string,
    name: string,
    onSuccess?: () => void
  ) => void;
  nameError?: string;
}

const SelectedClipView: React.FC<SelectedClipViewProps> = ({
  dataclip,
  onUnselect,
  isNextCronRun = false,
  canEditDataclip = false,
  onNameChange,
  nameError,
}) => {
  const [localName, setLocalName] = React.useState(dataclip.name || '');
  const [isEditing, setIsEditing] = React.useState(!dataclip.name);

  // Update local state when dataclip changes
  React.useEffect(() => {
    setLocalName(dataclip.name || '');
    setIsEditing(!dataclip.name);
  }, [dataclip.name]);

  const handleSubmit = React.useCallback(
    (e: React.FormEvent) => {
      e.preventDefault();
      if (localName !== (dataclip.name || '')) {
        onNameChange(dataclip.id, localName, () => {
          setIsEditing(false);
        });
      }
    },
    [localName, dataclip.name, dataclip.id, onNameChange]
  );

  const handleClear = React.useCallback(() => {
    setLocalName('');
    setIsEditing(true);
    onNameChange(dataclip.id, '');
  }, [dataclip.id, onNameChange]);

  return (
    <div className="relative h-full flex flex-col overflow-hidden">
      {/* Header bar */}
      <div className="flex items-center justify-between pt-2">
        <div className="flex gap-2 items-center text-sm text-gray-700">
          {isNextCronRun ? (
            <ClockIcon className="h-4 w-4 text-gray-500" />
          ) : (
            <DocumentTextIcon className="h-4 w-4 text-gray-500" />
          )}
          {dataclip.id}
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={onUnselect}
            className="relative inline-flex items-center rounded-md bg-white px-2 py-2 text-gray-400 ring-1 ring-gray-300 ring-inset hover:bg-gray-50 hover:text-gray-600 focus:z-10 transition-colors"
            title="Close"
          >
            <XMarkIcon className="h-4 w-4" />
          </button>
        </div>
      </div>

      <div className="flex flex-col flex-1 gap-2 py-3">
        {isNextCronRun && (
          <div className="alert-warning flex flex-col gap-1 px-3 py-2 rounded-md border">
            <span className="text-sm font-medium">
              Default Next Input for Cron
            </span>
            <span className="text-xs">
              This workflow has a "cron" trigger, and by default it will use the
              input below for its next run. You can override that by starting a
              manual run with an empty input or a custom input at any time.
            </span>
          </div>
        )}
        <div className="flex flex-row min-h-[28px] items-center mx-1">
          <div className="basis-1/2 font-medium text-secondary-700 text-sm">
            Type
          </div>
          <div className="basis-1/2 text-right">
            <DataclipTypePill type={dataclip.type} />
          </div>
        </div>
        <div className="flex flex-row min-h-[28px] items-center mx-1">
          <div className="basis-1/2 font-medium text-secondary-700 text-sm">
            Created at
          </div>
          <div className="basis-1/2 text-right text-sm text-nowrap">
            {formatDate(new Date(dataclip.inserted_at))}
          </div>
        </div>
        {(canEditDataclip || dataclip.name) && (
          <div className="flex flex-row min-h-[28px] items-center mx-1">
            <div className="basis-1/3 font-medium text-secondary-700 text-sm">
              Label
            </div>
            <div className="basis-2/3 text-right text-sm">
              {canEditDataclip ? (
                <div>
                  {isEditing ? (
                    <form onSubmit={handleSubmit}>
                      <div
                        className={`flex rounded-lg bg-white outline-1 -outline-offset-1 focus-within:outline-2 focus-within:-outline-offset-2 ${
                          nameError
                            ? 'outline-danger-300 focus-within:outline-danger-400'
                            : 'outline-slate-300 focus-within:outline-indigo-600'
                        }`}
                      >
                        <input
                          type="text"
                          name="credentialName"
                          autoComplete="off"
                          value={localName}
                          onChange={e => {
                            setLocalName(e.target.value);
                          }}
                          className="block min-w-0 grow  text-slate-900 placeholder:text-gray-400 focus:outline-none focus:ring-0 border-none sm:text-sm text-right"
                          placeholder="Enter Label"
                        />
                        <div className="flex py-1.5 pr-1.5">
                          <button type="submit">
                            <kbd className="inline-flex items-center rounded-sm border border-gray-200 px-1 font-sans text-xs text-gray-400">
                              ⏎
                            </kbd>
                          </button>
                        </div>
                      </div>
                      {nameError && (
                        <div className="mt-1 text-xs text-red-600">
                          {nameError}
                        </div>
                      )}
                    </form>
                  ) : (
                    <Pill
                      onClose={handleClear}
                      className="!p-2 !text-sm !gap-x-1"
                    >
                      <div>{dataclip.name}</div>
                    </Pill>
                  )}
                </div>
              ) : (
                dataclip.name
              )}
            </div>
          </div>
        )}
      </div>
      <DataclipViewer dataclipId={dataclip.id} />
    </div>
  );
};

export default SelectedClipView;
