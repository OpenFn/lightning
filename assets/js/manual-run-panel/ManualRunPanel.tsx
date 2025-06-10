import type { WithActionProps } from '#/react/lib/with-props';
import {
  DocumentIcon,
  PencilSquareIcon,
  QueueListIcon,
} from '@heroicons/react/24/outline';
import React from 'react';
import constructQuery from '../utils/constructQuery';
import { Tabs } from '../components/Tabs';
import { type Dataclip, FilterTypes, SeletableOptions } from './types';
import CustomView from './views/CustomView';
import EmptyView from './views/EmptyView';
import ExistingView from './views/ExistingView';
import SelectedClipView from './views/SelectedClipView';
import alterURLParams from '../utils/alterURLParams';
import useQuery from '../hooks/useQuery';

interface ManualRunPanelProps {
  job_id: string;
  selected_dataclip_id: string | null;
}

export const ManualRunPanel: WithActionProps<ManualRunPanelProps> = props => {
  const {
    active_panel,
    type,
    before,
    after,
    query: urlQuery,
    a: runId,
  } = useQuery(['active_panel', 'type', 'before', 'after', 'query', 'a']);
  const { pushEvent, pushEventTo, job_id, selected_dataclip_id, navigate } = props;
  const [selectedOption, setSelectedOption] = React.useState<SeletableOptions>(
    active_panel
      ? (Number(active_panel) as unknown as SeletableOptions)
      : SeletableOptions.EMPTY
  );
  const [recentclips, setRecentClips] = React.useState<Dataclip[]>([]);
  const [currentRunDataclip, setCurrentRunDataclip] = React.useState<Dataclip | null>(null);
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
  const formRef = React.useRef<HTMLFormElement>(null);

  const pushManualChange = React.useCallback((option: SeletableOptions) => {
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
  }, [pushEvent])

  const setSelectedDataclipHelper = React.useCallback((v: Dataclip | null) => {
    if (v) {
      pushEvent('manual_run_change', {
        manual: { dataclip_id: v.id },
      });
    } else {
      setSelectedOption(SeletableOptions.EXISTING);
      pushManualChange(SeletableOptions.EXISTING);
    }
    setSelectedDataclip(v);
  }, [pushEvent, pushManualChange])

  React.useEffect(() => {
    props.handleEvent('manual_run_created', payload => {
      if (payload.dataclip) {
        setSelectedDataclipHelper(payload.dataclip);
      }
    });
  }, [props, pushEvent]);
  // handling of form submit
  React.useEffect(() => {
    function handleSubmit(e: Event) {
      e.preventDefault();
      pushEvent('manual_run_submit', {});
    }
    const form = formRef.current;
    if (form) {
      form.addEventListener('submit', handleSubmit);
      return () => {
        form.removeEventListener('submit', handleSubmit);
      };
    }
  }, [pushEvent]);

  const parsedQuery = React.useMemo(() => {
    const filters = {
      type: selectedClipType || undefined,
      before: selectedDates.before || undefined,
      after: selectedDates.after || undefined,
    };

    const cleanFilters = Object.fromEntries(
      Object.entries(filters).filter(([_, value]) => value !== undefined)
    ) as Record<string, string>;

    return { query, filters: cleanFilters };
  }, [query, selectedClipType, selectedDates.before, selectedDates.after]);

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
    }
  }, []);

  // Fetch current run's dataclip if viewing a specific run
  React.useEffect(() => {
    if (runId && job_id) {
      pushEventTo(
        'get-run-input-dataclip',
        { run_id: runId, job_id: job_id },
        (response: any) => {
          if (response.dataclip) {
            setCurrentRunDataclip(response.dataclip);
          } else {
            setCurrentRunDataclip(null);
          }
        }
      );
    } else {
      setCurrentRunDataclip(null);
    }
  }, [runId, job_id, pushEvent]);

  React.useEffect(() => {
    pushEventTo(
      'search-selectable-dataclips',
      { job_id: job_id, search_text: '', limit: 10 },
      (response: any) => {
        const dataclips = response.dataclips as Dataclip[];
        setRecentClips(dataclips);
        if (selected_dataclip_id) {
          // First check if it's in the recent clips
          const activeClip = dataclips.find(d => d.id === selected_dataclip_id);
          if (activeClip) {
            setSelectedDataclipHelper(activeClip);
          } else if (currentRunDataclip && currentRunDataclip.id === selected_dataclip_id) {
            // If not in recent clips but matches current run dataclip, select it
            setSelectedDataclipHelper(currentRunDataclip);
          }
        }
      }
    );
  }, [pushEvent, job_id, selected_dataclip_id, currentRunDataclip, setSelectedDataclipHelper]);

  const handleSearchSumbit = React.useCallback(() => {
    const queryData = {
      ...(parsedQuery.query
        ? { query: parsedQuery.query }
        : { query: undefined }),
      ...parsedQuery.filters,
    };
    const q = constructQuery(queryData);
    navigate(alterURLParams(queryData).toString());
    pushManualChange(selectedOption)

    pushEventTo(
      'search-selectable-dataclips',
      { job_id: job_id, search_text: q, limit: 10 },
      (response: any) => {
        const dataclips = (response.dataclips || []) as Dataclip[];
        setRecentClips(dataclips);
      }
    );
  }, [job_id, parsedQuery, pushEvent, navigate]);

  React.useEffect(() => {
    if (!query.trim()) handleSearchSumbit();
  }, [query, handleSearchSumbit]);

  React.useEffect(() => {
    handleSearchSumbit();
  }, [selectedClipType, selectedDates]);

  const handleTabSelectionChange = React.useCallback((newSelection: string) => {
    const option = Number(newSelection) as SeletableOptions;
    navigate(alterURLParams({ active_panel: option.toString() }).toString());
    pushManualChange(option);
    setSelectedOption(option);
  }, [navigate, pushManualChange]);

  const allDataclips = React.useMemo(() => {
    const hasSearchCriteria = query.trim() || selectedClipType || selectedDates.before || selectedDates.after;
    if (hasSearchCriteria) {
      return recentclips;
    }
    
    // If not searching and we have a current run dataclip, put it at the top
    if (currentRunDataclip) {
      // Filter out current run dataclip from recent clips to avoid duplication
      const filteredRecentClips = recentclips.filter(clip => clip.id !== currentRunDataclip.id);
      
      // Put current dataclip first, then the filtered recent clips
      return [currentRunDataclip, ...filteredRecentClips];
    }
    
    // Default: just show recent clips
    return recentclips;
  }, [recentclips, currentRunDataclip, query]);

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
            setSelected={setSelectedDataclipHelper}
            selectedClipType={selectedClipType}
            setSelectedClipType={setSelectedClipType}
            clearFilter={clearFilter}
            selectedDates={selectedDates}
            setSelectedDates={setSelectedDates}
            currentRunDataclip={currentRunDataclip}
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
    setSelectedDataclipHelper,
    setSelectedDates,
    setSelectedClipType,
    clearFilter,
    pushEvent,
    handleSearchSumbit,
    currentRunDataclip,
  ]);

  return (
    <>
      <form ref={formRef} id="manual_run_form"></form>
      {selectedDataclip ? (
        <SelectedClipView
          dataclip={selectedDataclip}
          onUnselect={() => {
            setSelectedDataclipHelper(null);
          }}
        />
      ) : (
        <div className="grow overflow-auto no-scrollbar">
          <div className="flex flex-col h-full">
            <div className="flex justify-center flex-wrap mb-1">
              <Tabs
                options={[
                  { label: 'Empty', id: SeletableOptions.EMPTY.toString(), icon: DocumentIcon },
                  { label: 'Custom', id: SeletableOptions.CUSTOM.toString(), icon: PencilSquareIcon },
                  { label: 'Existing', id: SeletableOptions.EXISTING.toString(), icon: QueueListIcon },
                ]}
                initialSelection={selectedOption.toString()}
                onSelectionChange={handleTabSelectionChange}
                verticalCollapse={false}
              />
            </div>
            {innerView}
          </div>
        </div>
      )}
    </>
  );
};