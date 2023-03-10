import React, { useState, useCallback, useMemo, useEffect } from 'react';
import { ViewColumnsIcon, ChevronLeftIcon, ChevronRightIcon, ChevronUpIcon, ChevronDownIcon, DocumentTextIcon, SparklesIcon } from '@heroicons/react/24/outline'

import Docs from '../adaptor-docs/Docs';
import Editor from '../editor/Editor';
import Metadata from '../metadata-explorer/Explorer';
import loadMetadata from '../metadata-loader/metadata';

enum SettingsKeys {
  ORIENTATION = 'lightning.job-editor.orientation',
  SHOW_PANEL = 'lightning.job-editor.showPanel',
  ACTIVE_TAB = 'lightning.job-editor.activeTab',
};

const persistedSettings = localStorage.getItem('lightning.job-editor.settings')
const settings = persistedSettings ? JSON.parse(persistedSettings) : {
  [SettingsKeys.ORIENTATION]: 'h',
  [SettingsKeys.SHOW_PANEL]: true,
  [SettingsKeys.ACTIVE_TAB]: 'docs',
};

const persistSettings = () => localStorage.setItem('lightning.job-editor.settings', JSON.stringify(settings))

const iconStyle = "inline cursor-pointer h-6 w-6 mr-1"

type TabSpec = {
  label: string,
  id: string,
  icon: React.ReactNode
}

type TabsProps = { options: TabSpec[], onSelectionChange?: (newName: string) => void, verticalCollapse: boolean, initialSelection?: String };

const Tabs = ({ options, onSelectionChange, verticalCollapse, initialSelection }: TabsProps) => {
  const [selected, setSelected ] = useState(initialSelection);

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
       {/* TODO need to support more information in each tab */}
       {options.map(({ label, id, icon }) => {
          const style = id === selected ? 
            'bg-gray-100 text-gray-700' : 'text-gray-500 hover:text-gray-700'
          return <div
            onClick={() => handleSelectionChange(id)}
            className={`${style} select-none rounded-md px-3 py-2 text-sm font-medium cursor-pointer flex-row whitespace-nowrap`}
            >
              {React.createElement(icon, { className: iconStyle })}
              <span className="align-bottom">{label}</span>
            </div>
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
  const [selectedTab, setSelectedTab] = useState(() => settings[SettingsKeys.ACTIVE_TAB]);
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
    persistSettings();
  }, [vertical]);

  const toggleShowPanel = useCallback(() => {
    setShowPanel(!showPanel);
    resize();
    settings[SettingsKeys.SHOW_PANEL] =! showPanel;
    persistSettings()
  }, [showPanel]);

  const handleSelectionChange = (newSelection: string) => {
    setSelectedTab(newSelection);
    settings[SettingsKeys.ACTIVE_TAB] = newSelection;
    persistSettings();
    if (!showPanel) {
      toggleShowPanel();
    }
  };

  const resize = () => {
    // terrible solution to resizing the editor
    document.dispatchEvent(new Event('update-layout'));
  };

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
          options={[
            { label: 'Docs', id: 'docs', icon: DocumentTextIcon },
            { label: 'Metadata', id: 'metadata', icon: SparklesIcon } // TODO if active, colour it
          ]}
          initialSelection={selectedTab}
          onSelectionChange={handleSelectionChange}
          verticalCollapse={!vertical && !showPanel}
        />
        <ViewColumnsIcon className={iconStyle} onClick={toggleOrientiation} />
        <CollapseIcon className={iconStyle} onClick={toggleShowPanel} />
      </div>
      {showPanel && 
        <div className={`flex flex-1 ${vertical ? 'overflow-auto' : 'overflow-hidden'} px-2`}>
          {selectedTab === 'docs' && <Docs adaptor={adaptor} />}
          {selectedTab === 'metadata' && <Metadata adaptor={adaptor} metadata={metadata} />}
        </div>
      }
    </div>
  </div>
  </>)
}