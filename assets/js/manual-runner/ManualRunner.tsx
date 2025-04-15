import { MonacoEditor } from "#/monaco";
import type { WithActionProps } from "#/react/lib/with-props";
import { DocumentIcon, PencilSquareIcon, DocumentArrowUpIcon, MagnifyingGlassIcon, DocumentTextIcon, InformationCircleIcon } from "@heroicons/react/24/outline"
import { CloudArrowUpIcon } from "@heroicons/react/24/solid";
import React from "react";
interface ManualRunnerProps {
  smth: number
}

const iconStyle = 'h-4 w-4 text-grey-400 mr-1';

enum SeletableOptions {
  NONE,
  EMPTY,
  CUSTOM,
  IMPORT
}

export const ManualRunner: WithActionProps<ManualRunnerProps> = () => {
  const [selectedOption, setSelectedOption] = React.useState<SeletableOptions>(SeletableOptions.NONE);

  const innerView = React.useMemo(() => {
    switch (selectedOption) {
      case SeletableOptions.NONE:
        return <NoneView />
      case SeletableOptions.IMPORT:
        return <ImportView />
      case SeletableOptions.CUSTOM:
        return <CustomView />
      case SeletableOptions.EMPTY:
        return <EmptyView />
      default:
        return <></>
    }
  }, [selectedOption])

  const getActive = (v: SeletableOptions) => {
    if (selectedOption === v)
      return " border-primary-600 text-primary-600 font-bold bg-slate-100"
    return ""
  }

  return <div className="px-4 py-6">
    <div className="flex flex-col gap-3">
      <div className="font-bold flex justify-center">Select Input</div>
      <div className="flex gap-4 justify-center">
        <button type="button" onClick={() => { setSelectedOption(SeletableOptions.EMPTY) }} className={"border rounded-md px-3 py-1 flex justify-center items-center gap-1 text-sm hover:bg-slate-100 hover:border-primary-300 group" + getActive(SeletableOptions.EMPTY)}>
          <DocumentIcon className={`${iconStyle} transition-transform duration-300 group-hover:scale-110 group-hover:text-primary-600`} /> Empty
        </button>
        <button type="button" onClick={() => { setSelectedOption(SeletableOptions.CUSTOM) }} className={"border rounded-md px-3 py-1 flex justify-center items-center gap-1 text-sm hover:bg-slate-100 hover:border-primary-300 group" + getActive(SeletableOptions.CUSTOM)}>
          <PencilSquareIcon className={`${iconStyle} transition-transform duration-300 group-hover:scale-110 group-hover:text-primary-600`} /> Custom
        </button>
        <button type="button" onClick={() => { setSelectedOption(SeletableOptions.IMPORT) }} className={"border rounded-md px-3 py-1 flex justify-center items-center gap-1 text-sm hover:bg-slate-100 hover:border-primary-300 group" + getActive(SeletableOptions.IMPORT)}>
          <DocumentArrowUpIcon className={`${iconStyle} transition-transform duration-300 group-hover:scale-110 group-hover:text-primary-600`} /> Import
        </button>
      </div>
      {innerView}
    </div>
  </div>
}

const NoneView = () => {
  return <>
    <hr className="my-3" />
    <div className="flex flex-col gap-3">
      <div className="relative">
        <input type="email" className="w-full bg-transparent placeholder:text-slate-400 text-slate-700 text-sm border border-slate-200 rounded-md pr-3 pl-10 py-2 transition duration-300 ease focus:outline-none focus:border-slate-400 hover:border-slate-300 shadow-sm focus:shadow" placeholder="Search field" />
        <div className="absolute left-1 top-1 rounded p-1.5 border border-transparent text-center text-sm" type="button">
          <MagnifyingGlassIcon className={iconStyle} />
        </div>
      </div>
      <div className="flex items-center justify-between border rounded px-3 py-1 cursor-pointer hover:bg-slate-100 hover:border-primary-600 group">
        <div className="flex gap-1 items-center text-base"> <DocumentTextIcon className={`${iconStyle} transition-transform duration-300 group-hover:scale-110 group-hover:text-primary-600`} /> dataclip-one </div>
        <div className="text-xs">{new Date().toISOString()}</div>
      </div>
      <div className="flex items-center justify-between border rounded px-3 py-1 cursor-pointer hover:bg-slate-100 hover:border-primary-600 group">
        <div className="flex gap-1 items-center text-base"> <DocumentTextIcon className={`${iconStyle} transition-transform duration-300 group-hover:scale-110 group-hover:text-primary-600`} /> dataclip-two </div>
        <div className="text-xs">{new Date().toISOString()}</div>
      </div>
      <div className="flex items-center justify-between border rounded px-3 py-1 cursor-pointer hover:bg-slate-100 hover:border-primary-600 group">
        <div className="flex gap-1 items-center text-base"> <DocumentTextIcon className={`${iconStyle} transition-transform duration-300 group-hover:scale-110 group-hover:text-primary-600`} /> dataclip-three </div>
        <div className="text-xs">{new Date().toISOString()}</div>
      </div>
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