import {
  DocumentIcon,
  PencilSquareIcon,
  QueueListIcon,
} from '@heroicons/react/24/outline';
import React from 'react';

import type { WithActionProps } from '#/react/lib/with-props';

import { Tabs } from '../components/Tabs';
import useQuery from '../hooks/useQuery';
import alterURLParams from '../utils/alterURLParams';
import constructQuery from '../utils/constructQuery';
import type { RunStep } from '../workflow-store/store';

import { type Dataclip, FilterTypes, SeletableOptions } from './types';
import CustomView from './views/CustomView';
import EmptyView from './views/EmptyView';
import ExistingView from './views/ExistingView';
import SelectedClipView from './views/SelectedClipView';

interface ManualRunPanelProps {
  job_id: string;
  fixedHeight: boolean;
  onRunStepChange?: (runStep: RunStep | null) => void;
  onDataclipChange?: (dataclip: Dataclip | null) => void;
}

export const ManualRunPanel: WithActionProps<ManualRunPanelProps> = props => {
  const {
    active_panel,
    type,
    before,
    after,
    query: urlQuery,
    a: runId,
    named_only,
  } = useQuery([
    'active_panel',
    'type',
    'before',
    'after',
    'query',
    'named_only',
    'a',
  ]);
  const {
    pushEvent,
    pushEventTo,
    job_id,
    navigate,
    fixedHeight = false,
    onRunStepChange,
    onDataclipChange,
  } = props;

  const [selectedOption, setSelectedOption] = React.useState<SeletableOptions>(
    active_panel
      ? (Number(active_panel) as unknown as SeletableOptions)
      : SeletableOptions.EMPTY
  );
  const [recentclips, setRecentClips] = React.useState<Dataclip[]>([]);
  const [currentRunDataclip, setCurrentRunDataclip] =
    React.useState<Dataclip | null>(null);
  const [nextCronRunDataclipId, setNextCronRunDataclipId] = React.useState<
    string | null
  >(null);
  const [canEditDatclip, setCanEditDatclip] = React.useState<boolean>(false);
  const [query, setQuery] = React.useState(urlQuery ? urlQuery : '');
  const [selectedDataclip, setSelectedDataclip] =
    React.useState<Dataclip | null>();
  const [selectedClipType, setSelectedClipType] = React.useState<string>(
    type ? type : ''
  );
  const [selectedDates, setSelectedDates] = React.useState({
    before: before ? before : '',
    after: after ? after : '',
  });
  const [namedOnly, setNamedOnly] = React.useState<boolean>(
    named_only === 'true'
  );
  const [nameError, setNameError] = React.useState<string>('');
  const formRef = React.useRef<HTMLFormElement>(null);

  const pushManualChange = React.useCallback(
    (option: SeletableOptions) => {
      switch (option) {
        case SeletableOptions.EMPTY:
          pushEvent('manual_run_change', {
            manual: {
              body: '{}',
              dataclip_id: null,
            },
          });
          break;
        case SeletableOptions.CUSTOM:
        case SeletableOptions.EXISTING:
          pushEvent('manual_run_change', {
            manual: {
              body: null,
              dataclip_id: null,
            },
          });
          break;
      }
    },
    [pushEvent]
  );

  const selectDataclipForManualRun = React.useCallback(
    (dataclip: Dataclip | null) => {
      if (dataclip) {
        pushEvent('manual_run_change', {
          manual: { dataclip_id: dataclip.id },
        });
      } else {
        setSelectedOption(SeletableOptions.EXISTING);
        pushManualChange(SeletableOptions.EXISTING);
      }
      onDataclipChange?.(dataclip);
      setSelectedDataclip(dataclip);
      setNameError(''); // Clear any existing error when switching dataclips
    },
    [
      pushEvent,
      setSelectedOption,
      pushManualChange,
      setSelectedDataclip,
      onDataclipChange,
    ]
  );

  React.useEffect(() => {
    return props.handleEvent('manual_run_created', (payload: unknown) => {
      const typedPayload = payload as { dataclip?: Dataclip };
      if (typedPayload.dataclip) {
        // Update currentRunDataclip since this is now the active run's dataclip
        setCurrentRunDataclip(typedPayload.dataclip);
        selectDataclipForManualRun(typedPayload.dataclip);
      }
    });
  }, [props.handleEvent, selectDataclipForManualRun, setCurrentRunDataclip]);

  // handling of form submit
  React.useEffect(() => {
    const form = formRef.current;
    if (!form) return; // Early return

    function handleSubmit(e: Event) {
      e.preventDefault();
      pushEvent('manual_run_submit', {});
    }

    form.addEventListener('submit', handleSubmit);
    return () => {
      form.removeEventListener('submit', handleSubmit);
    };
  }, [pushEvent]);

  const parsedQuery = React.useMemo(() => {
    const filters = {
      type: selectedClipType || undefined,
      before: selectedDates.before || undefined,
      after: selectedDates.after || undefined,
      named_only: namedOnly || undefined,
    };

    const cleanFilters = Object.fromEntries(
      Object.entries(filters).filter(([, value]) => value !== undefined)
    ) as Record<string, string>;

    return { query, filters: cleanFilters };
  }, [
    query,
    selectedClipType,
    selectedDates.before,
    selectedDates.after,
    namedOnly,
  ]);

  const clearFilter = React.useCallback((type: FilterTypes) => {
    switch (type) {
      case FilterTypes.DATACLIP_TYPE:
        setSelectedClipType('');
        break;
      case FilterTypes.BEFORE_DATE:
        setSelectedDates(p => ({ before: '', after: p.after }));
        break;
      case FilterTypes.AFTER_DATE:
        setSelectedDates(p => ({ before: p.before, after: '' }));
        break;
      case FilterTypes.NAMED_ONLY:
        setNamedOnly(false);
        break;
    }
  }, []);

  // Fetch current run's dataclip if viewing a specific run
  React.useEffect(() => {
    if (runId && job_id) {
      pushEventTo(
        'get-run-step-and-input-dataclip',
        { run_id: runId, job_id: job_id },
        (response: unknown) => {
          const typedResponse = response as {
            dataclip: Dataclip | null;
            run_step: RunStep | null;
          };
          if (typedResponse.dataclip) {
            setCurrentRunDataclip(typedResponse.dataclip);
            // Auto-select the current run's dataclip when viewing a specific run
            selectDataclipForManualRun(typedResponse.dataclip);
          } else {
            setCurrentRunDataclip(null);
            selectDataclipForManualRun(null);
          }
          onRunStepChange?.(typedResponse.run_step);
        }
      );
    } else {
      setCurrentRunDataclip(null);
      onRunStepChange?.(null);
    }
  }, [runId, job_id, pushEventTo, selectDataclipForManualRun, onRunStepChange]);

  React.useEffect(() => {
    pushEventTo(
      'search-selectable-dataclips',
      { job_id: job_id, search_text: '', limit: 10 },
      (response: unknown) => {
        const typedResponse = response as {
          dataclips: Dataclip[];
          next_cron_run_dataclip_id: string | null;
          can_edit_dataclip: boolean;
        };
        setRecentClips(typedResponse.dataclips);
        setNextCronRunDataclipId(typedResponse.next_cron_run_dataclip_id);
        setCanEditDatclip(typedResponse.can_edit_dataclip);

        // Auto-select the next cron run dataclip if it exists (for cron jobs)
        if (typedResponse.next_cron_run_dataclip_id && !runId) {
          const nextCronDataclip = typedResponse.dataclips.find(
            clip => clip.id === typedResponse.next_cron_run_dataclip_id
          );
          if (nextCronDataclip) {
            selectDataclipForManualRun(nextCronDataclip);
          }
        }
      }
    );
  }, [pushEvent, job_id, runId, selectDataclipForManualRun]);

  const handleSearchSumbit = React.useCallback(() => {
    const queryData = {
      ...(parsedQuery.query
        ? { query: parsedQuery.query }
        : { query: undefined }),
      ...parsedQuery.filters,
    };
    const q = constructQuery(queryData);
    navigate(alterURLParams(queryData).toString());
    pushManualChange(selectedOption);

    pushEventTo(
      'search-selectable-dataclips',
      { job_id: job_id, search_text: q, limit: 10 },
      (response: unknown) => {
        const typedResponse = response as {
          dataclips: Dataclip[];
          next_cron_run_dataclip_id: string | null;
          can_edit_dataclip: boolean;
        };
        setRecentClips(typedResponse.dataclips);
        setNextCronRunDataclipId(typedResponse.next_cron_run_dataclip_id);
        setCanEditDatclip(typedResponse.can_edit_dataclip);

        // Note: Auto-selection of next cron run is handled in the initial useEffect only
        // We don't auto-select here to avoid re-selecting when filters are cleared
      }
    );
  }, [job_id, parsedQuery, pushEvent, navigate, selectedOption]);

  const handleDataclipNameChange = React.useCallback(
    (dataclipId: string, name: string, onSuccess?: () => void) => {
      pushEventTo(
        'update-dataclip-name',
        {
          dataclip_id: dataclipId,
          name: name,
        },
        (response: unknown) => {
          const typedResponse = response as {
            dataclip?: Dataclip;
            error?: string;
          };
          if (typedResponse.dataclip) {
            const updatedDataclip = typedResponse.dataclip;

            // Clear any existing error
            setNameError('');

            // Update selected dataclip
            setSelectedDataclip(updatedDataclip);

            // Update dataclip in recentclips list
            setRecentClips(clips =>
              clips.map(clip =>
                clip.id === updatedDataclip.id ? updatedDataclip : clip
              )
            );

            // Update current run dataclip if it's the same
            if (currentRunDataclip?.id === updatedDataclip.id) {
              setCurrentRunDataclip(updatedDataclip);
            }

            // Call success callback if provided
            if (onSuccess) {
              onSuccess();
            }
          } else if (typedResponse.error) {
            // Set error message
            setNameError(typedResponse.error);
          }
        }
      );
    },
    [
      pushEventTo,
      setSelectedDataclip,
      setRecentClips,
      currentRunDataclip,
      setCurrentRunDataclip,
    ]
  );

  React.useEffect(() => {
    if (!query.trim()) handleSearchSumbit();
  }, [query, handleSearchSumbit]);

  React.useEffect(() => {
    handleSearchSumbit();
  }, [selectedClipType, selectedDates]);

  const handleTabSelectionChange = React.useCallback(
    (newSelection: string) => {
      const option = Number(newSelection) as SeletableOptions;
      navigate(alterURLParams({ active_panel: option.toString() }).toString());
      pushManualChange(option);
      setSelectedOption(option);
    },
    [navigate, pushManualChange]
  );

  const allDataclips = React.useMemo(() => {
    const hasSearchCriteria =
      query.trim() ||
      selectedClipType ||
      selectedDates.before ||
      selectedDates.after;
    if (hasSearchCriteria) {
      return recentclips;
    }

    // If we have a next cron run, the backend already put it at the top, so just use as-is
    if (nextCronRunDataclipId) {
      return recentclips;
    }

    // If not searching and we have a current run dataclip, put it at the top
    if (currentRunDataclip) {
      // Filter out current run dataclip from recent clips to avoid duplication
      const filteredRecentClips = recentclips.filter(
        clip => clip.id !== currentRunDataclip.id
      );

      // Put current dataclip first, then the filtered recent clips
      return [currentRunDataclip, ...filteredRecentClips];
    }

    // Default: just show recent clips
    return recentclips;
  }, [recentclips, currentRunDataclip, nextCronRunDataclipId, query]);

  const innerView = React.useMemo(() => {
    switch (selectedOption) {
      case SeletableOptions.EXISTING:
        return (
          <ExistingView
            onSubmit={handleSearchSumbit}
            query={query}
            filters={parsedQuery.filters}
            dataclips={allDataclips}
            setQuery={setQuery}
            setSelected={selectDataclipForManualRun}
            selectedClipType={selectedClipType}
            setSelectedClipType={setSelectedClipType}
            clearFilter={clearFilter}
            selectedDates={selectedDates}
            setSelectedDates={setSelectedDates}
            namedOnly={namedOnly}
            setNamedOnly={setNamedOnly}
            fixedHeight={fixedHeight}
            currentRunDataclip={currentRunDataclip}
            nextCronRunDataclipId={nextCronRunDataclipId}
          />
        );
      case SeletableOptions.CUSTOM:
        return <CustomView pushEvent={pushEvent} />;
      case SeletableOptions.EMPTY:
        return <EmptyView />;
      default:
        return <></>;
    }
  }, [
    selectedOption,
    query,
    allDataclips,
    parsedQuery.filters,
    selectedClipType,
    selectedDates,
    namedOnly,
    selectDataclipForManualRun,
    setSelectedDates,
    setSelectedClipType,
    setNamedOnly,
    clearFilter,
    pushEvent,
    handleSearchSumbit,
    currentRunDataclip,
    nextCronRunDataclipId,
    fixedHeight,
  ]);

  return (
    <>
      <form ref={formRef} id="manual_run_form" className="hidden"></form>
      {selectedDataclip ? (
        <div className="grow overflow-hidden">
          <SelectedClipView
            dataclip={selectedDataclip}
            onUnselect={() => {
              selectDataclipForManualRun(null);
            }}
            isNextCronRun={nextCronRunDataclipId === selectedDataclip.id}
            onNameChange={handleDataclipNameChange}
            canEditDataclip={canEditDatclip}
            nameError={nameError}
          />
        </div>
      ) : (
        <div className="grow overflow-visible no-scrollbar">
          <div className="flex flex-col h-full">
            <div className="flex justify-center flex-wrap mb-1">
              <Tabs
                options={[
                  {
                    label: 'Empty',
                    id: SeletableOptions.EMPTY.toString(),
                    icon: DocumentIcon,
                  },
                  {
                    label: 'Custom',
                    id: SeletableOptions.CUSTOM.toString(),
                    icon: PencilSquareIcon,
                  },
                  {
                    label: 'Existing',
                    id: SeletableOptions.EXISTING.toString(),
                    icon: QueueListIcon,
                  },
                ]}
                initialSelection={selectedOption.toString()}
                onSelectionChange={handleTabSelectionChange}
                collapsedVertical={false}
              />
            </div>
            {innerView}
          </div>
        </div>
      )}
    </>
  );
};
