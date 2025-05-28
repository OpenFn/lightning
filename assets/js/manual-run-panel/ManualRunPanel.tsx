import type { WithActionProps } from '#/react/lib/with-props';
import {
  DocumentIcon,
  PencilSquareIcon,
  QueueListIcon,
} from '@heroicons/react/24/outline';
import React from 'react';
import constructQuery from '../utils/constructQuery';
import { type Dataclip, FilterTypes, SeletableOptions } from './types';
import CustomView from './views/CustomView';
import EmptyView from './views/EmptyView';
import ExistingView from './views/ExistingView';
import SelectedClipView from './views/SelectedClipView';
import updateURLParams from '../utils/updateURLParams';
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
  } = useQuery(['active_panel', 'type', 'before', 'after', 'query']);
  const { pushEvent, job_id, selected_dataclip_id } = props;
  const [selectedOption, setSelectedOption] = React.useState<SeletableOptions>(
    active_panel
      ? (Number(active_panel) as unknown as SeletableOptions)
      : SeletableOptions.EMPTY
  );
  const [recentclips, setRecentClips] = React.useState<Dataclip[]>([]);
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

  React.useEffect(() => {
    props.handleEvent('manual_run_created', payload => {
      if (payload.dataclip) {
        setSelectedDataclip(payload.dataclip);
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
    const a = { query, filters: {} as Record<string, string | undefined> };
    if (typeof selectedClipType === 'string' && selectedClipType)
      a.filters['type'] = selectedClipType;
    else a.filters['type'] = undefined;
    if (typeof selectedDates.before === 'string' && selectedDates.before)
      a.filters['before'] = selectedDates.before;
    else a.filters['before'] = undefined;
    if (typeof selectedDates.after === 'string' && selectedDates.after)
      a.filters['after'] = selectedDates.after;
    else a.filters['after'] = undefined;
    return a;
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

  React.useEffect(() => {
    pushEvent(
      'search-selectable-dataclips',
      { job_id: job_id, search_text: '', limit: 10 },
      response => {
        const dataclips = response.dataclips as Dataclip[];
        setRecentClips(dataclips);
        if (selected_dataclip_id) {
          const activeClip = dataclips.find(d => d.id === selected_dataclip_id);
          if (activeClip) {
            setSelectedDataclip(activeClip);
          }
        }
      }
    );
  }, [pushEvent, job_id, selected_dataclip_id]);

  const handleSearchSumbit = React.useCallback(() => {
    const queryData = {
      ...(parsedQuery.query
        ? { query: parsedQuery.query }
        : { query: undefined }),
      ...parsedQuery.filters,
    };
    const q = constructQuery(queryData);
    updateURLParams(queryData);

    pushEvent(
      'search-selectable-dataclips',
      { job_id: job_id, search_text: q, limit: 10 },
      response => {
        const dataclips = (response.dataclips || []) as Dataclip[];
        setRecentClips(dataclips);
      }
    );
  }, [job_id, parsedQuery, pushEvent]);

  React.useEffect(() => {
    if (!query.trim()) handleSearchSumbit();
  }, [query, handleSearchSumbit]);

  React.useEffect(() => {
    handleSearchSumbit();
  }, [selectedClipType, selectedDates]);

  React.useEffect(() => {
    if (selectedDataclip) {
      pushEvent('manual_run_change', {
        manual: { dataclip_id: selectedDataclip.id },
      });
    } else {
      pushEvent('manual_run_change', {
        manual: { dataclip_id: null, body: null },
      });
    }
  }, [selectedDataclip, pushEvent]);

  React.useEffect(() => {
    switch (selectedOption) {
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
    updateURLParams({ active_panel: selectedOption.toString() });
  }, [selectedOption, pushEvent]);

  const innerView = React.useMemo(() => {
    switch (selectedOption) {
      case SeletableOptions.EXISTING:
        return (
          <ExistingView
            onSubmit={handleSearchSumbit}
            query={query}
            filters={parsedQuery.filters}
            dataclips={recentclips}
            setQuery={setQuery}
            setSelected={setSelectedDataclip}
            selectedClipType={selectedClipType}
            setSelectedClipType={setSelectedClipType}
            clearFilter={clearFilter}
            selectedDates={selectedDates}
            setSelectedDates={setSelectedDates}
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
    recentclips,
    parsedQuery.filters,
    selectedClipType,
    selectedDates,
    setSelectedDates,
    setSelectedClipType,
    clearFilter,
    pushEvent,
    handleSearchSumbit,
  ]);

  const getActive = (v: SeletableOptions) => {
    if (selectedOption === v)
      return ' border-primary-600 text-primary-600 bg-slate-100';
    return '';
  };

  const selectOptionHandler = (option: SeletableOptions) => () => {
    setSelectedOption(option);
  };

  return (
    <>
      <form ref={formRef} id="manual_run_form"></form>
      {selectedDataclip ? (
        <SelectedClipView
          dataclip={selectedDataclip}
          onUnselect={() => {
            setSelectedDataclip(null);
          }}
        />
      ) : (
        <div className="grow overflow-auto no-scrollbar">
          <div className="flex flex-col gap-3 h-full">
            <div className="flex md:gap-2 sm:gap-1 gap-4 justify-center flex-wrap">
              <button
                type="button"
                onClick={selectOptionHandler(SeletableOptions.EMPTY)}
                className={
                  'border text-sm rounded-md px-3 py-1 flex justify-center items-center gap-1 hover:bg-slate-100 hover:border-primary-300 group' +
                  getActive(SeletableOptions.EMPTY)
                }
              >
                <DocumentIcon
                  className={`text-gray-600 w-4 h-4 group-hover:scale-110 group-hover:text-primary-600`}
                />
                Empty
              </button>
              <button
                type="button"
                onClick={selectOptionHandler(SeletableOptions.CUSTOM)}
                className={
                  'border text-sm rounded-md px-3 py-1 flex justify-center items-center gap-1 hover:bg-slate-100 hover:border-primary-300 group' +
                  getActive(SeletableOptions.CUSTOM)
                }
              >
                <PencilSquareIcon
                  className={`text-gray-600 w-4 h-4 group-hover:scale-110 group-hover:text-primary-600`}
                />
                Custom
              </button>
              <button
                type="button"
                onClick={selectOptionHandler(SeletableOptions.EXISTING)}
                className={
                  'border text-sm rounded-md px-3 py-1 flex justify-center items-center gap-1 hover:bg-slate-100 hover:border-primary-300 group' +
                  getActive(SeletableOptions.EXISTING)
                }
              >
                <QueueListIcon
                  className={`text-gray-600 w-4 h-4 group-hover:scale-110 group-hover:text-primary-600`}
                />
                Existing
              </button>
            </div>
            <hr className="my-2" />
            {innerView}
          </div>
        </div>
      )}
    </>
  );
};
