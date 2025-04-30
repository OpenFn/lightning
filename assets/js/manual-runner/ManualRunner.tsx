import { MonacoEditor } from "#/monaco";
import { DataclipViewer } from "#/react/components/DataclipViewer";
import type { WithActionProps } from "#/react/lib/with-props";
import { CheckIcon, DocumentArrowUpIcon, DocumentIcon, DocumentTextIcon, InformationCircleIcon, MagnifyingGlassIcon, PencilSquareIcon, Squares2X2Icon, XMarkIcon } from "@heroicons/react/24/outline";
import { CloudArrowUpIcon, XCircleIcon } from "@heroicons/react/24/solid";
import React from "react";
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
  DATACLIP_TYPE = "type"
}

export const ManualRunner: WithActionProps<ManualRunnerProps> = (props) => {
  const { pushEvent, job_id } = props;
  const [selectedOption, setSelectedOption] = React.useState<SeletableOptions>(SeletableOptions.NONE);
  const [recentclips, setRecentClips] = React.useState<Dataclip[]>([]);
  const [query, setQuery] = React.useState("");
  const [selectedclip, setSelectedclip] = React.useState<Dataclip | null>(null);
  const [selectedcliptype, setSelectedClipType] = React.useState<string>("");

  const parsedQuery = React.useMemo(() => {
    const a = parseFilter(query);
    if (selectedcliptype)
      a.filters["type"] = selectedcliptype
    return a;
  }, [query, selectedcliptype])

  const clearFilter = (type: FilterTypes) => {
    switch (type) {
      case FilterTypes.DATACLIP_TYPE:
        setSelectedClipType("")
        delete parsedQuery.filters[FilterTypes.DATACLIP_TYPE]
        setQuery(constructQuery(parsedQuery))
    }
  }

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
          clearFilter={clearFilter} />
      case SeletableOptions.IMPORT:
        return <ImportView />
      case SeletableOptions.CUSTOM:
        return <CustomView />
      case SeletableOptions.EMPTY:
        return <EmptyView />
      default:
        return <></>
    }
  }, [selectedOption, query, recentclips, parsedQuery.filters, selectedcliptype, setSelectedClipType, clearFilter])

  const getActive = (v: SeletableOptions) => {
    if (selectedOption === v)
      return " border-primary-600 text-primary-600 font-bold bg-slate-100"
    return ""
  }

  const selectOptionHandler = (option: SeletableOptions) => () => {
    setSelectedOption(p => p === option ? SeletableOptions.NONE : option);
  }

  if (selectedclip)
    return <>
      <div className="flex-0">
        <div className="my-2" onClick={() => { setSelectedclip(null) }}>
          <button className="flex w-full items-center justify-between px-4 py-2 bg-[#dbe9fe] text-[#3562dd] rounded-md hover:bg-[#b7d3fd]">
            <span>{selectedclip.id}</span>
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
  return <div className="px-4 py-6">
    <div className="flex flex-col gap-3">
      <div className="font-bold flex justify-center">Select Input</div>
      <div className="flex gap-4 justify-center">
        <button type="button" onClick={selectOptionHandler(SeletableOptions.EMPTY)} className={"border rounded-md px-3 py-1 flex justify-center items-center gap-1 text-sm hover:bg-slate-100 hover:border-primary-300 group" + getActive(SeletableOptions.EMPTY)}>
          {selectedOption === SeletableOptions.EMPTY ? <XCircleIcon className={closeStyle} /> : <DocumentIcon className={`${iconStyle} transition-transform duration-300 group-hover:scale-110 group-hover:text-primary-600`} />}
          Empty
        </button>
        <button type="button" onClick={selectOptionHandler(SeletableOptions.CUSTOM)} className={"border rounded-md px-3 py-1 flex justify-center items-center gap-1 text-sm hover:bg-slate-100 hover:border-primary-300 group" + getActive(SeletableOptions.CUSTOM)}>
          {selectedOption === SeletableOptions.CUSTOM ? <XCircleIcon className={closeStyle} /> : <PencilSquareIcon className={`${iconStyle} transition-transform duration-300 group-hover:scale-110 group-hover:text-primary-600`} />}
          Custom
        </button>
        <button type="button" onClick={selectOptionHandler(SeletableOptions.IMPORT)} className={"border rounded-md px-3 py-1 flex justify-center items-center gap-1 text-sm hover:bg-slate-100 hover:border-primary-300 group" + getActive(SeletableOptions.IMPORT)}>
          {selectedOption === SeletableOptions.IMPORT ? <XCircleIcon className={closeStyle} /> : <DocumentArrowUpIcon className={`${iconStyle} transition-transform duration-300 group-hover:scale-110 group-hover:text-primary-600`} />}
          Import
        </button>
      </div>
      {innerView}
    </div>
  </div>
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
  clearFilter: (v: FilterTypes) => void
}> = ({ dataclips, query, setQuery, setSelected, filters, selectedcliptype, setSelectedclipType, clearFilter }) => {
  const [typesOpen, setTypesOpen] = React.useState(false);

  const pills = Object.entries(filters).map(([key, value]) => <div className="inline-flex items-center gap-x-0.5 rounded-md bg-blue-100 px-2 py-1 text-xs font-medium text-blue-700">{key}: {value} <button onClick={() => clearFilter(FilterTypes.DATACLIP_TYPE)} className="group relative -mr-1 h-3.5 w-3.5 rounded-sm hover:bg-blue-600/20"><XMarkIcon /> </button></div>)
  return <>
    <hr className="my-3" />
    <div className="flex flex-col gap-3">
      <div>
        <div className="relative flex gap-2">
          <input value={query} onChange={e => { setQuery(e.target.value) }} type="email" className="w-full bg-transparent placeholder:text-slate-400 text-slate-700 text-sm border border-slate-200 rounded-md pr-3 pl-10 py-2 transition duration-300 ease focus:outline-none focus:border-slate-400 hover:border-slate-300 shadow-sm focus:shadow" placeholder="Search field" />
          <div className="absolute left-1 top-1 rounded p-1.5 border border-transparent text-center text-sm">
            <MagnifyingGlassIcon className={iconStyle} />
          </div>
          <div className="relative inline-block">
            <button onClick={() => { setTypesOpen(p => !p) }} className="border rounded-md px-3 py-1 h-full flex justify-center items-center hover:bg-slate-100 hover:border-primary-300">
              <Squares2X2Icon className="w-6 h-6 text-slate-700" />
            </button>
            <ul className={`absolute z-10 mt-1 bg-white border border-gray-300 rounded-md shadow-lg w-auto right-0 ${typesOpen ? "" : "hidden"} `}>
              {DataclipTypes.map(type => <li key={type} onClick={() => { setSelectedclipType(type === selectedcliptype ? "" : type) }} className={`px-4 py-2 hover:bg-blue-100 cursor-pointer text-nowrap flex items-center gap-2 text-base text-slate-700 ${type === selectedcliptype ? "bg-blue-200 text-blue-700 font-semibold" : ""}`}> {type} {selectedcliptype === type ? <CheckIcon className={iconStyle} /> : null} </li>)}
            </ul>
          </div>
        </div>
        <div className="flex gap-1 mt-2">
          {pills}
        </div>
      </div>
      {dataclips.length ? dataclips.map(clip => {
        return <div onClick={() => { setSelected(clip); }} className="flex items-center justify-between border rounded px-3 py-1 cursor-pointer hover:bg-slate-100 hover:border-primary-600 group">
          <div className="flex gap-1 items-center text-sm"> <DocumentTextIcon className={`${iconStyle} transition-transform duration-300 group-hover:scale-110 group-hover:text-primary-600`} /> {truncateUid(clip.id)} </div>
          <div className="text-xs">{clip.updated_at}</div>
        </div>
      }) :
        <div className="text-center text-sm">No dataclips found. pick an option above</div>}
    </div>
  </>
}

const ImportView = () => {
  return <>
    <div className="col-span-full">
      <div className="mt-2 flex justify-center rounded-lg border border-dashed border-gray-900/25 px-6 py-10">
        <div className="text-center">
          <CloudArrowUpIcon className="mx-auto size-12 text-gray-300" />
          <div className="mt-4 flex text-sm/6 text-gray-600">
            <label htmlFor="file-upload" className="relative cursor-pointer rounded-md bg-white font-semibold text-indigo-600 focus-within:ring-2 focus-within:ring-indigo-600 focus-within:ring-offset-2 focus-within:outline-hidden hover:text-indigo-500">
              <span>Upload a file</span>
              <input id="file-upload" name="file-upload" type="file" className="sr-only" />
            </label>
            <p className="pl-1">or drag and drop</p>
          </div>
          <p className="text-xs/5 text-gray-600">JSON up to 3MB</p>
        </div>
      </div>
    </div>
  </>
}

const EmptyView = () => {
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

const CustomView = () => {
  return <div className='relative h-[420px]'>
    <div className="font-semibold mb-3 text-gray-600">Create a new input</div>
    <MonacoEditor
      defaultLanguage="json"
      theme="default"
      value=""
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
  }).format(date);
}