import React, { useState, useCallback, useMemo, useEffect } from 'react';
import { ViewColumnsIcon, ChevronLeftIcon, ChevronRightIcon, ChevronUpIcon, ChevronDownIcon } from '@heroicons/react/24/outline'

import Docs from '../adaptor-docs/Docs';
import Editor from '../editor/Editor';
import Metadata from '../metadata-explorer/Explorer';
import loadMetadata from '../metadata-loader/metadata';

enum SettingsKeys {
  ORIENTATION = 'lightning.job-editor.orientation',
  SHOW_PANEL = 'lightning.job-editor.showPanel',
};

const persistedSettings = localStorage.getItem('lightning.job-editor.settings')
const settings = persistedSettings ? JSON.parse(persistedSettings) : {
  [SettingsKeys.ORIENTATION]: 'h',
  [SettingsKeys.SHOW_PANEL]: true,
};

const persistSettings = () => localStorage.setItem('lightning.job-editor.settings', JSON.stringify(settings))

const iconStyle = "cursor-pointer h-6 w-6"

const Tabs = ({ options, onSelectionChange, verticalCollapse }: { options: string[], onSelectionChange?: (newName: string) => void, verticalCollapse: boolean }) => {
  const [selected, setSelected ] = useState(options[0]);

  const handleSelectionChange = (name: string) => {
    if (name !== selected) {
      setSelected(name);
      onSelectionChange?.(name);
    }
  }

  const style = verticalCollapse ? {
    writingMode: 'vertical-rl',
    textOrientation: 'mixed'
  } : {};

  return (
    <nav className={`flex space-${verticalCollapse?'y':'x'}-2 w-full`} aria-label="Tabs" style={style}>
       {options.map((name) => {
          const style = name === selected ? 
            'bg-gray-100 text-gray-700' : 'text-gray-500 hover:text-gray-700'
          return <div onClick={() => handleSelectionChange(name)} className={`${style} select-none rounded-md px-3 py-2 text-sm font-medium cursor-pointer`}>{name}</div>
        })
      }
    </nav>
  )
}

type JobEditorProps = {
  adaptor?: string;
  source?: string;
  onSourceChanged?: (src: string) => void;
}

export default ({ adaptor, source, onSourceChanged }: JobEditorProps) => {
  const [vertical, setVertical] = useState(() => settings[SettingsKeys.ORIENTATION] === 'v');
  const [showPanel, setShowPanel] = useState(() => settings[SettingsKeys.SHOW_PANEL]);
  const [selectedTab, setSelectedTab] = useState('Docs');
  const [metadata, setMetadata] = useState<any>();

  useEffect(() => {
    loadMetadata(adaptor).then((m) => {
      setMetadata(m)
    })
  }, [adaptor]);

  const toggleOrientiation = useCallback(() => {
    setVertical(!vertical)
    resize();
    settings[SettingsKeys.ORIENTATION] = vertical ? 'h' : 'v';
    persistSettings()
  }, [vertical])

  const toggleShowPanel = useCallback(() => {
    setShowPanel(!showPanel)
    resize();
    settings[SettingsKeys.SHOW_PANEL] =! showPanel;
    persistSettings()
  }, [showPanel])

  const handleSelectionChange = (newSelection: string) => {
    setSelectedTab(newSelection);
    if (!showPanel) {
      toggleShowPanel()
    }
  }

  const resize = () => {
    // terrible solution to resizing the editor
    const e = new Event('update-layout');
    document.dispatchEvent(e)
  }

  const CollapseIcon = useMemo(() => {
    if (vertical) {
      return showPanel ? ChevronDownIcon : ChevronUpIcon;
    } else {
      return showPanel ? ChevronRightIcon : ChevronLeftIcon;
    }
  }, [vertical, showPanel])

  // TODO too many complex style rules embedded in this - is there a better approach?
  return (<>
  <div className="cursor-pointer" >
  </div>
  <div className={`flex h-full v-full flex-${vertical ? 'col' : 'row'}`}>
    <div className="flex flex-1 rounded-md border border-secondary-300 shadow-sm bg-vs-dark">
      <Editor source={source} adaptor={adaptor} metadata={metadata} onChange={onSourceChanged} />
    </div>
    <div className={`${showPanel ? 'flex flex-col flex-1 overflow-auto' : ''} bg-white`}>
      <div className={
        ['flex',
        `flex-${!vertical && !showPanel ? 'col-reverse items-center' : 'row'}`,
        'w-full',
        'justify-items-end',
        'sticky',
        vertical ? 'pt-2' : 'pl-2'
      ].join(' ')}>
        <Tabs
          options={['Docs', 'Metadata']}
          onSelectionChange={handleSelectionChange}
          verticalCollapse={!vertical && !showPanel}
        />
        <ViewColumnsIcon className={iconStyle} onClick={toggleOrientiation} />
        <CollapseIcon className={iconStyle} onClick={toggleShowPanel} />
      </div>
      {showPanel && 
        <div className={`flex-1 ${!vertical && 'overflow-auto' || ''} px-2`}>
          {selectedTab === 'Docs' && <Docs adaptor={adaptor} />}
          {selectedTab === 'Metadata' && <Metadata adaptor={adaptor} metadata={metadata} />}
        </div>
      }
    </div>
  </div>
  </>)
}