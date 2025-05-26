import type { WithActionProps } from '#/react/lib/with-props';
import {
  DocumentIcon,
  PencilSquareIcon,
  QueueListIcon
} from '@heroicons/react/24/outline';
import React from 'react';
import constructQuery from '../utils/constructQuery';
import { type Dataclip, FilterTypes, SeletableOptions } from './types';
import CustomView from './views/CustomView';
import EmptyView from './views/EmptyView';
import ExistingView from './views/ExistingView';
import SelectedClipView from './views/SelectedClipView';
interface ManualRunPanelProps {
  job_id: string;
  selected_dataclip_id: string | null;
}

export const ManualRunPanel: WithActionProps<ManualRunPanelProps> = props => {
  const { pushEvent, job_id, selected_dataclip_id } = props;
  const [selectedOption, setSelectedOption] = React.useState<SeletableOptions>(
    selected_dataclip_id ? SeletableOptions.EXISTING :
      SeletableOptions.EMPTY
  );
  const [recentclips, setRecentClips] = React.useState<Dataclip[]>([]);
  const [query, setQuery] = React.useState('');
  const [selectedclip, setSelectedclip] = React.useState<Dataclip | null>();
  const [selectedcliptype, setSelectedClipType] = React.useState<string>('');
  const [selectedDates, setSelectedDates] = React.useState({
    before: '',
    after: '',
  });
  const formRef = React.useRef<HTMLFormElement>(null);

  React.useEffect(() => {
    props.handleEvent('manual_run_created', payload => {
      if (payload.dataclip) {
        setSelectedOption(SeletableOptions.EXISTING);
        setTimeout(() => {
          setSelectedclip(payload.dataclip);
        }, 0);
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
    const a = { query, filters: {} as Record<string, string> };
    if (selectedcliptype) a.filters['type'] = selectedcliptype;
    if (selectedDates.before) a.filters['before'] = selectedDates.before;
    if (selectedDates.after) a.filters['after'] = selectedDates.after;
    return a;
  }, [query, selectedcliptype, selectedDates.before, selectedDates.after]);

  const clearFilter = React.useCallback(
    (type: FilterTypes) => {
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
    },
    []
  );

  React.useEffect(() => {
    pushEvent(
      'search-selectable-dataclips',
      { job_id: job_id, limit: 10 },
      response => {
        const dataclips = response.dataclips as Dataclip[];
        setRecentClips(dataclips);
        if (selected_dataclip_id) {
          const activeClip = dataclips.find(d => d.id === selected_dataclip_id);
          if (activeClip) setSelectedclip(activeClip);
        }
      }
    );
  }, [pushEvent, job_id, selected_dataclip_id]);

  const handleSearchSumbit = React.useCallback(() => {
    const q = constructQuery(parsedQuery);
    pushEvent(
      'search-selectable-dataclips',
      { job_id: job_id, search_text: q, limit: 10 },
      response => {
        const dataclips = (response.dataclips || []) as Dataclip[];
        setRecentClips(dataclips);
      }
    );
  }, [job_id, parsedQuery, pushEvent])

  React.useEffect(() => {
    if (!query.trim()) handleSearchSumbit();
  }, [query, handleSearchSumbit])

  React.useEffect(() => {
    handleSearchSumbit();
  }, [selectedcliptype, selectedDates]);

  React.useEffect(() => {
    if (selectedclip) {
      pushEvent('manual_run_change', {
        manual: {
          dataclip_id: selectedclip.id,
        },
      });
    } else {
      pushEvent('manual_run_change', {
        manual: {
          dataclip_id: null,
          body: null,
        },
      });
    }
  }, [selectedclip, pushEvent]);

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
            setSelected={setSelectedclip}
            selectedcliptype={selectedcliptype}
            setSelectedclipType={setSelectedClipType}
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
    selectedcliptype,
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
      {selectedclip ? (
        <SelectedClipView dataclip={selectedclip} onUnselect={() => { setSelectedclip(null) }} />
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