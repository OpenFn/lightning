import { MonacoEditor } from "#/monaco";
import { DataclipViewer } from "#/react/components/DataclipViewer";
import type { WithActionProps } from "#/react/lib/with-props";
import { CalendarDaysIcon, CheckCircleIcon, CheckIcon, DocumentArrowUpIcon, DocumentIcon, DocumentTextIcon, InformationCircleIcon, MagnifyingGlassIcon, PencilSquareIcon, RectangleGroupIcon, XMarkIcon } from "@heroicons/react/24/outline";
import { XCircleIcon } from "@heroicons/react/24/solid";
import React from "react";
import FileUploader from "./FileUploader";
interface ManualRunnerProps {
  job_id: string
}

const iconStyle = 'h-4 w-4 text-grey-400';
const closeStyle = 'h-4 w-4 text-red-400';

enum SeletableOptions {
  NONE,
  EMPTY,
  CUSTOM,
  IMPORT
}

interface Dataclip {
  id: string;
  body: {
    data: Record<string, unknown>;
    request: {
      headers: {
        accept: string;
        host: string;
        "user-agent": string;
      };
      method: string;
      path: string[];
      query_params: Record<string, unknown>;
    };
  };
  request: null;
  type: "http_request";
  wiped_at: string | null;
  project_id: string;
  inserted_at: string;
  updated_at: string;
}

const DataclipTypes = ["http_request", "global", "step_result", "saved_input", "kafka"]
enum FilterTypes {
  DATACLIP_TYPE = "type",
  BEFORE_DATE = "before",
  AFTER_DATE = "after"
}

type SetDates = React.Dispatch<React.SetStateAction<{
  before: string;
  after: string;
}>>

export const ManualRunner: WithActionProps<ManualRunnerProps> = (props) => {
  const { pushEvent, job_id } = props;
  const [selectedOption, setSelectedOption] = React.useState<SeletableOptions>(SeletableOptions.NONE);
  const [recentclips, setRecentClips] = React.useState<Dataclip[]>([]);
  const [query, setQuery] = React.useState("");
  const [selectedclip, setSelectedclip] = React.useState<Dataclip | null>(null);
  const [selectedcliptype, setSelectedClipType] = React.useState<string>("");
  const [selectedDates, setSelectedDates] = React.useState({ before: "", after: "" })
  const formRef = React.useRef<HTMLFormElement>(null)


  React.useEffect(() => {
    props.handleEvent("manual_run_created", payload => {
      if (payload.dataclip) {
        setSelectedclip(payload.dataclip);
        setSelectedOption(SeletableOptions.NONE)
      }
    })
  }, [props])
  // handling of form submit
  React.useEffect(() => {
    function handleSubmit(e: Event) {
      e.preventDefault();
      pushEvent("manual_run_submit", {});
    }
    const form = formRef.current;
    if (form) {
      form.addEventListener("submit", handleSubmit);
      return () => { form.removeEventListener("submit", handleSubmit); }
    }
  }, [pushEvent]);

  const parsedQuery = React.useMemo(() => {
    const a = parseFilter(query);
    if (selectedcliptype)
      a.filters["type"] = selectedcliptype
    if (selectedDates.before)
      a.filters["before"] = selectedDates.before
    if (selectedDates.after)
      a.filters["after"] = selectedDates.after
    return a;
  }, [query, selectedcliptype, selectedDates.before, selectedDates.after])

  const clearFilter = React.useCallback((type: FilterTypes) => {
    console.log("clearning:", type)
    delete parsedQuery.filters[type]
    setQuery(constructQuery(parsedQuery))
    switch (type) {
      case FilterTypes.DATACLIP_TYPE:
        setSelectedClipType("")
        break;
      case FilterTypes.BEFORE_DATE:
        setSelectedDates(p => ({ before: "", after: p.after }))
        break;
      case FilterTypes.AFTER_DATE:
        setSelectedDates(p => ({ before: p.before, after: "" }))
        break;
    }
  }, [parsedQuery])

  React.useEffect(() => {
    pushEvent("get-selectable-dataclips", { job_id: job_id, limit: 5 }, (response) => {
      const dataclips = response.dataclips as Dataclip[];
      setRecentClips(dataclips);
    })
  }, [pushEvent, job_id])

  React.useEffect(() => {
    // FIXME: search currently errors on phx side
    const q = constructQuery(parsedQuery);
    pushEvent("search-selectable-dataclips", { job_id: job_id, search_text: q, limit: 5 }, (response) => {
      const dataclips = (response.dataclips || []) as Dataclip[];
      console.log("farhan", dataclips)
      setRecentClips(dataclips);
    })
  }, [pushEvent, job_id, parsedQuery])

  // Add effect to handle dataclip selection changes
  React.useEffect(() => {
    if (selectedclip) {
      pushEvent("manual_run_change", {
        manual: {
          dataclip_id: selectedclip.id,
        }
      });
    } else {
      pushEvent("manual_run_change", {
        manual: {
          dataclip_id: null,
          body: null
        }
      });
    }
  }, [selectedclip, pushEvent]);

  React.useEffect(() => {
    switch (selectedOption) {
      case SeletableOptions.EMPTY:
        pushEvent("manual_run_change", {
          manual: {
            body: "{}",
            dataclip_id: null
          }
        })
        break;
      case SeletableOptions.CUSTOM:
      case SeletableOptions.NONE:
      case SeletableOptions.IMPORT:
        pushEvent("manual_run_change", {
          manual: {
            body: null,
            dataclip_id: null
          }
        });
        break;
    }
  }, [selectedOption, pushEvent])

  const innerView = React.useMemo(() => {
    switch (selectedOption) {
      case SeletableOptions.NONE:
        return <NoneView
          query={query}
          filters={parsedQuery.filters}
          dataclips={recentclips}
          setQuery={setQuery}
          setSelected={setSelectedclip}
          selectedcliptype={selectedcliptype}
          setSelectedclipType={setSelectedClipType}
          clearFilter={clearFilter}
          selectedDates={selectedDates}
          setSelectedDates={setSelectedDates} />
      case SeletableOptions.IMPORT:
        return <ImportView pushEvent={pushEvent} />
      case SeletableOptions.CUSTOM:
        return <CustomView pushEvent={pushEvent} />
      case SeletableOptions.EMPTY:
        return <EmptyView />
      default:
        return <></>
    }
  }, [selectedOption, query, recentclips, parsedQuery.filters, selectedcliptype, selectedDates, setSelectedDates, setSelectedClipType, clearFilter, pushEvent])

  const getActive = (v: SeletableOptions) => {
    if (selectedOption === v)
      return " border-primary-600 text-primary-600 bg-slate-100"
    return ""
  }

  const selectOptionHandler = (option: SeletableOptions) => () => {
    setSelectedOption(p => p === option ? SeletableOptions.NONE : option);
  }


  return <>
    <form ref={formRef} id="manual_run_form"></form>
    {selectedclip ?
      <>
        <div className="flex-0">
          <div className="my-2" onClick={() => { setSelectedclip(null) }}>
            <button className="flex w-full items-center justify-between px-4 py-2 bg-[#dbe9fe] text-[#3562dd] rounded-md hover:bg-[#b7d3fd]">
              <div className="truncate">{selectedclip.id}</div>
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 ml-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
          <div className="flex flex-row">
            <div className="basis-1/2 font-semibold text-secondary-700 text-xs xl:text-base">
              Type
            </div>
            <div className="basis-1/2 text-right">
              <DataClipTypePill type={selectedclip.type} />
            </div>
          </div>
          <div className="flex flex-row mt-4">
            <div className="basis-1/2 font-semibold text-secondary-700 text-xs xl:text-base">
              Created at
            </div>
            <div className="basis-1/2 text-right">
              {formatDate(new Date(selectedclip.inserted_at))}
            </div>
          </div>
        </div>
        <DataclipViewer dataclipId={selectedclip.id} />
      </>
      :
      <div className="px-4 py-6 grow">
        <div className="flex flex-col gap-3 h-full">
          <div className="font-bold flex justify-center">Select Input</div>
          <div className="flex gap-4 justify-center flex-wrap">
            <button type="button" onClick={selectOptionHandler(SeletableOptions.EMPTY)} className={"border min-w-[147px] text-base rounded-md px-3 py-1 flex justify-center items-center gap-1 hover:bg-slate-100 hover:border-primary-300 group" + getActive(SeletableOptions.EMPTY)}>
              {selectedOption === SeletableOptions.EMPTY ? <XCircleIcon className={closeStyle} /> : <DocumentIcon className={`text-gray-600 w-4 h-4 transition-transform duration-300 group-hover:scale-110 group-hover:text-primary-600`} />}
              Empty
            </button>
            <button type="button" onClick={selectOptionHandler(SeletableOptions.CUSTOM)} className={"border min-w-[147px] text-base rounded-md px-3 py-1 flex justify-center items-center gap-1 hover:bg-slate-100 hover:border-primary-300 group" + getActive(SeletableOptions.CUSTOM)}>
              {selectedOption === SeletableOptions.CUSTOM ? <XCircleIcon className={closeStyle} /> : <PencilSquareIcon className={`text-gray-600 w-4 h-4 transition-transform duration-300 group-hover:scale-110 group-hover:text-primary-600`} />}
              Custom
            </button>
            <button type="button" onClick={selectOptionHandler(SeletableOptions.IMPORT)} className={"border min-w-[147px] text-base rounded-md px-3 py-1 flex justify-center items-center gap-1 hover:bg-slate-100 hover:border-primary-300 group" + getActive(SeletableOptions.IMPORT)}>
              {selectedOption === SeletableOptions.IMPORT ? <XCircleIcon className={closeStyle} /> : <DocumentArrowUpIcon className={`text-gray-600 w-4 h-4 transition-transform duration-300 group-hover:scale-110 group-hover:text-primary-600`} />}
              Import
            </button>
          </div>
          <hr className="my-3" />
          {innerView}
        </div>
      </div>
    }
  </>
}

function truncateUid(id: string) {
  return id.split('-')[0];
}

function constructQuery(payload: { query: string, filters: Record<string, string> }) {
  let output = payload.query;
  Object.entries(payload.filters).forEach(([key, value]) => output += ` ${key}:${value}`);
  return output;
}
function parseFilter(input: string) {
  const pattern = /\w+:\s*(\w+(-\w+)*)/g;
  const matches: string[] = [];
  let match;

  // Find all matches for the pattern in the line
  while ((match = pattern.exec(input)) !== null) {
    matches.push(match[0]); // Capture the full match
  }

  // Find the rest of the line (remove the matched parts)
  let rest = input;
  const filters: Record<string, string> = {};
  const allowedKeys = Object.values(FilterTypes);
  matches.forEach(m => {
    rest = rest.replace(m, '').trim();
    const [key, value] = m.split(/:\s*/);
    if (key && value && allowedKeys.includes(key)) filters[key] = value;
  });

  return { query: rest, filters }
}

const NoneView: React.FC<{
  dataclips: Dataclip[],
  query: string,
  setQuery: (v: string) => void,
  setSelected: (v: Dataclip) => void,
  filters: Record<string, string>
  selectedcliptype: string,
  setSelectedclipType: (v: string) => void,
  clearFilter: (v: FilterTypes) => void,
  selectedDates: { before: string, after: string },
  setSelectedDates: SetDates
}> = ({ dataclips, query, setQuery, setSelected, filters, selectedcliptype, setSelectedclipType, clearFilter, selectedDates, setSelectedDates }) => {
  const [typesOpen, setTypesOpen] = React.useState(false);
  const [dateOpen, setDateOpen] = React.useState(false);
  const calendarRef = useOutsideClick<HTMLDivElement>(() => { setDateOpen(false) });
  const typesRef = useOutsideClick<HTMLUListElement>(() => { setTypesOpen(false) });

  const pills = Object.entries(filters).map(([key, value]) => <div className="inline-flex items-center gap-x-0.5 rounded-md bg-blue-100 px-2 py-1 text-xs font-medium text-blue-700">{key}: {value} <button onClick={() => { clearFilter(key as FilterTypes) }} className="group relative -mr-1 h-3.5 w-3.5 rounded-sm hover:bg-blue-600/20"><XMarkIcon /> </button></div>)
  return <>
    <div className="flex flex-col gap-3">
      <div>
        <div className="relative flex gap-2">
          <input value={query} onChange={e => { setQuery(e.target.value) }} type="email" className="w-full bg-transparent placeholder:text-slate-400 text-slate-700 text-sm border border-slate-200 rounded-md pr-3 pl-10 py-2 transition duration-300 ease focus:outline-none focus:border-slate-400 hover:border-slate-300 shadow-sm focus:shadow" placeholder="Search field" />
          <div className="absolute left-1 top-1 rounded p-1.5 border border-transparent text-center text-sm">
            <MagnifyingGlassIcon className={iconStyle} />
          </div>
          <div className="relative inline-block">
            <button onClick={() => { setDateOpen(p => !p) }} className="border rounded-md px-3 py-1 h-full flex justify-center items-center hover:bg-slate-100 hover:border-slate-300">
              <CalendarDaysIcon className="w-6 h-6 text-slate-700" />
            </button>
            <div ref={calendarRef} className={`absolute z-10 mt-1 p-2 bg-white rounded-md shadow-lg ring-1 ring-black/5 focus:outline-none w-auto right-0 ${dateOpen ? "" : "hidden"} `}>
              <div className="py-3" role="none">
                <div className="px-4 py-1 text-gray-500 text-sm">
                  Filter by Date
                </div>
                <div className="px-4 py-1 text-gray-700 text-sm">
                  <label htmlFor="date-after">Date After</label>
                  <input
                    value={selectedDates.after}
                    id="date-after"
                    onChange={(e) => { setSelectedDates((p) => ({ after: e.target.value, before: p.before })) }}
                    className="focus:outline focus:outline-2 focus:outline-offset-1 block w-full rounded-lg text-slate-900 focus:ring-0 sm:text-sm sm:leading-6"
                    type="date"
                  />
                </div>
                <div className="px-4 py-1 text-gray-700 text-sm">
                  <label htmlFor="date-before">Date Before</label>
                  <input
                    value={selectedDates.before}
                    id="date-before"
                    onChange={(e) => { setSelectedDates((p) => ({ after: p.after, before: e.target.value })) }}
                    className="focus:outline focus:outline-2 focus:outline-offset-1 block w-full rounded-lg text-slate-900 focus:ring-0 sm:text-sm sm:leading-6"
                    type="date"
                  />
                </div>
              </div>
            </div>
          </div>
          <div className="relative inline-block">
            <button onClick={() => { setTypesOpen(p => !p) }} className="border rounded-md px-3 py-1 h-full flex justify-center items-center hover:bg-slate-100 hover:border-slate-300">
              <RectangleGroupIcon className="w-6 h-6 text-slate-700" />
            </button>
            <ul ref={typesRef} className={`absolute z-10 mt-1 bg-white ring-1 ring-black/5 focus:outline-none rounded-md shadow-lg right-0 w-auto ${typesOpen ? "" : "hidden"} `}>
              {DataclipTypes.map(type => { return <li key={type} onClick={() => { setSelectedclipType(type === selectedcliptype ? "" : type) }} className={`px-4 py-2 hover:bg-slate-100 cursor-pointer text-nowrap flex items-center gap-2 text-base text-slate-700 ${type === selectedcliptype ? "bg-blue-200 text-blue-700" : ""}`}> {type} <CheckIcon strokeWidth={3} className={`${iconStyle} ${type !== selectedcliptype ? "invisible" : ""}`} /> </li> })}
            </ul>
          </div>
        </div>
        <div className="flex gap-1 mt-2">
          {pills}
        </div>
      </div>
      {dataclips.length ? dataclips.map(clip => {
        return <div onClick={() => { setSelected(clip); }} className="flex items-center justify-between border rounded-md px-3 py-2 cursor-pointer hover:bg-slate-100 hover:border-primary-600 group">
          <div className="flex gap-1 items-center text-base"> <DocumentTextIcon className={`${iconStyle} transition-transform duration-300 group-hover:scale-110 group-hover:text-primary-600`} /> {truncateUid(clip.id)} </div>
          <div className="text-xs truncate ml-2">{formatDate(new Date(clip.updated_at))}</div>
        </div>
      }) :
        <div className="text-center text-sm">No dataclips found. pick an option above</div>}
    </div>
  </>
}


async function readFileContent(file: File): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();

    reader.onload = () => { resolve(reader.result as string); }
    reader.onerror = () => { reject(reader.error); }

    reader.readAsText(file);
  });
}


const ImportView: React.FC<{ pushEvent: (event: string, data: any) => void }> = ({ pushEvent }) => {
  const [importedFiles, setImportedFiles] = React.useState<File[]>([]);
  const [isValidJSON, setIsValidJSON] = React.useState(true);

  function uploadFiles(f: File[]) {
    setImportedFiles([...importedFiles, ...f]);
  }

  function deleteFile(indexImg: number) {
    setImportedFiles(prev => prev.filter((_, index) => index !== indexImg));
  }

  React.useEffect(() => {
    if (importedFiles.length === 1) {
      const file = importedFiles[0];
      if (!file) return;
      void readFileContent(file).then(content => {
        // check whether JSON is valid
        try {
          JSON.parse(content);
          setIsValidJSON(true);
          pushEvent("manual_run_change", {
            manual: {
              body: content,
              dataclip_id: null
            }
          });
        } catch (e: any) {
          setIsValidJSON(false)
        }
        return;
      })
    } else {
      setIsValidJSON(true)
      pushEvent("manual_run_change", {
        manual: {
          body: null,
          dataclip_id: null
        }
      });
    }
  }, [importedFiles, importedFiles.length, pushEvent])

  return <>
    {
      !isValidJSON ?
        <div className="text-red-700 text-sm flex gap-1 mb-1 items-center"><InformationCircleIcon className={iconStyle} /> File has invalid JSON content</div>
        :
        null
    }
    <FileUploader
      currFiles={importedFiles}
      onUpload={uploadFiles}
      onDelete={deleteFile}
      count={1}
      formats={["json"]} />
  </>
}

const EmptyView: React.FC = () => {

  return <div className="flex flex-col items-center gap-2 text-xs py-5">
    <div className="flex gap-1">
      <InformationCircleIcon className={`${iconStyle} text-yellow-700`} />
      An empty input data would be used for this run
    </div>
    <div>
      <div>i.e <span className="bg-slate-700 text-white font-mono p-1 rounded">&#123;&#125;</span></div>
    </div>
  </div>
}

const CustomView: React.FC<{ pushEvent: (event: string, data: any) => void }> = ({ pushEvent }) => {
  const [editorValue, setEditorValue] = React.useState("");

  const isEmpty = React.useMemo(() => !editorValue.trim(), [editorValue])
  const isValidJson = React.useMemo(() => {
    try {
      JSON.parse(editorValue);
      return true;
    } catch (e) {
      return false;
    }
  }, [editorValue])

  const handleEditorChange = React.useCallback((value: string) => {
    setEditorValue(value);
    if (isValidJson)
      pushEvent("manual_run_change", {
        manual: {
          body: value,
          dataclip_id: null
        }
      });
  }, [isValidJson, pushEvent]);

  return <div className='relative h-[420px]'>
    <div className="font-semibold mb-3 text-gray-600">Create a new input</div>
    {
      (isEmpty || !isValidJson) ?
        <div className="text-red-700 text-sm flex gap-1 mb-1 items-center"><InformationCircleIcon className={iconStyle} /> {isEmpty ? "Custom input can't be empty" : "Invalid JSON format"}</div>
        :
        <div className="text-green-700 text-sm flex gap-1 mb-1 items-center"><CheckCircleIcon className={iconStyle} />Correct JSON format</div>
    }
    <MonacoEditor
      defaultLanguage="json"
      theme="default"
      value={editorValue}
      onChange={handleEditorChange}
      loading={<div>Loading...</div>}
      options={{
        readOnly: false,
        lineNumbersMinChars: 3,
        tabSize: 2,
        scrollBeyondLastLine: false,
        overviewRulerLanes: 0,
        overviewRulerBorder: false,
        fontFamily: 'Fira Code VF',
        fontSize: 14,
        fontLigatures: true,
        minimap: {
          enabled: false,
        },
        wordWrap: 'on',
      }}
    />
  </div>
}

type DataClipType = 'step_result' | 'http_request' | 'global' | 'saved_input';

interface DataClipTypePillProps {
  type: DataClipType;
}

const DataClipTypePill: React.FC<DataClipTypePillProps> = ({ type = "saved_input" }) => {
  const baseClasses = 'px-2 py-1 rounded-full inline-block text-sm font-mono';

  const typeClasses = {
    step_result: 'bg-purple-500 text-purple-900',
    http_request: 'bg-green-500 text-green-900',
    global: 'bg-blue-500 text-blue-900',
    saved_input: 'bg-yellow-500 text-yellow-900',
  }[type] || '';

  return (
    <div className={`${baseClasses} ${typeClasses}`}>
      {type}
    </div>
  );
};

// to be moved to a utils file
function formatDate(date: Date, locale: string = 'en-US'): string {
  return new Intl.DateTimeFormat(locale, {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).format(date).replace(/\//g, "-");
}

function useOutsideClick<T extends HTMLElement>(callback: () => void) {
  const ref = React.useRef<T>(null);

  React.useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (ref.current && !ref.current.contains(event.target as Node)) {
        callback();
      }
    }

    document.addEventListener('mousedown', handleClickOutside);
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [callback]);

  return ref;
}