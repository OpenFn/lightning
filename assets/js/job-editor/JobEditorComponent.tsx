import React, { useState, useCallback, useMemo, useEffect } from 'react';
import {
  ViewColumnsIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
  ChevronUpIcon,
  ChevronDownIcon,
  DocumentTextIcon,
  SparklesIcon,
} from '@heroicons/react/24/outline';

import Docs from '../adaptor-docs/Docs';
import Editor from '../editor/Editor';
import Metadata from '../metadata-explorer/Explorer';
import { Tabs, iconStyle } from '../components/Tabs';

enum SettingsKeys {
  ORIENTATION = 'lightning.job-editor.orientation',
  SHOW_PANEL = 'lightning.job-editor.showPanel',
  ACTIVE_TAB = 'lightning.job-editor.activeTab',
}

// TODO maybe a usePersist() hook which takes defaults as an argument and returns a) the persisted values and b) a setter (shallow merge)
const persistedSettings = localStorage.getItem('lightning.job-editor.settings');
const settings = persistedSettings
  ? JSON.parse(persistedSettings)
  : {
    [SettingsKeys.ORIENTATION]: 'h',
    [SettingsKeys.SHOW_PANEL]: false,
  };

const persistSettings = () =>
  localStorage.setItem(
    'lightning.job-editor.settings',
    JSON.stringify(settings)
  );

type JobEditorComponentProps = {
  adaptor: string;
  source: string;
  disabled?: boolean;
  disabledMessage?: string;
  metadata?: object | true;
  onSourceChanged?: (src: string) => void;
};

export default ({
  adaptor,
  source,
  disabled,
  disabledMessage,
  metadata,
  onSourceChanged,
}: JobEditorComponentProps) => {
  const [vertical, setVertical] = useState(
    () => settings[SettingsKeys.ORIENTATION] === 'v'
  );
  const [showPanel, setShowPanel] = useState(
    () => settings[SettingsKeys.SHOW_PANEL]
  );
  const [selectedTab, setSelectedTab] = useState('docs');

  const toggleOrientiation = useCallback(() => {
    setVertical(!vertical);
    settings[SettingsKeys.ORIENTATION] = vertical ? 'h' : 'v';
    persistSettings();
  }, [vertical]);

  const toggleShowPanel = useCallback(() => {
    setShowPanel(!showPanel);
    settings[SettingsKeys.SHOW_PANEL] = !showPanel;
    persistSettings();
  }, [showPanel]);

  const handleSelectionChange = (newSelection: string) => {
    setSelectedTab(newSelection);
    if (!showPanel) {
      toggleShowPanel();
    }
  };

  const CollapseIcon = useMemo(() => {
    if (vertical) {
      return showPanel ? ChevronDownIcon : ChevronUpIcon;
    } else {
      return showPanel ? ChevronRightIcon : ChevronLeftIcon;
    }
  }, [vertical, showPanel]);

  return (
    <>
      <div className="cursor-pointer"></div>
      <div className={`flex h-full flex-${vertical ? 'col' : 'row'}`}>
        <div className="flex-1 rounded-md overflow-hidden">
          <Editor
            source={source}
            adaptor={adaptor}
            metadata={metadata === true ? undefined : metadata}
            disabled={disabled}
            disabledMessage={disabledMessage}
            onChange={onSourceChanged}
          />
        </div>
        <div
          className={`${showPanel ? 'flex flex-1 flex-col z-10 overflow-hidden' : ''
            } ${vertical ? 'pt-2' : 'pl-2'} bg-white`}
        >
          <div
            className={[
              'flex',
              !vertical && !showPanel
                ? 'flex-col-reverse items-center'
                : 'flex-row',
              'w-full',
              'justify-items-end',
              'sticky',
            ].join(' ')}
          >
            <Tabs
              options={[
                { label: 'Docs', id: 'docs', icon: DocumentTextIcon },
                { label: 'Metadata', id: 'metadata', icon: SparklesIcon }, // TODO if active, colour it
              ]}
              initialSelection={selectedTab}
              onSelectionChange={handleSelectionChange}
              verticalCollapse={!vertical && !showPanel}
            />
            <div
              className={`flex select-none flex-1 text-right py-2 ${!showPanel && !vertical ? 'flex-col-reverse' : 'flex-row'
                }`}
            >
              <ViewColumnsIcon
                className={`${iconStyle} ${!vertical ? 'rotate-90' : ''}`}
                onClick={toggleOrientiation}
                title="Toggle panel orientation"
              />
              <CollapseIcon
                className={iconStyle}
                onClick={toggleShowPanel}
                title="Collapse panel"
              />
            </div>
          </div>
          {showPanel && (
            <div
              className={`flex flex-1 ${vertical ? 'overflow-auto' : 'overflow-hidden'
                }`}
            >
              {selectedTab === 'docs' && <Docs adaptor={adaptor} />}
              {selectedTab === 'metadata' && (
                <Metadata adaptor={adaptor} metadata={metadata} />
              )}
            </div>
          )}
        </div>
      </div>
    </>
  );
};
