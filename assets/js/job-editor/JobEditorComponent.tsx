import {
  ViewColumnsIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
  ChevronUpIcon,
  ChevronDownIcon,
  DocumentTextIcon,
  SparklesIcon,
} from '@heroicons/react/24/outline';
import React, { useState, useCallback, useMemo, useEffect } from 'react';

import Docs from '../adaptor-docs/Docs';
import { Tabs } from '../components/Tabs';
import Editor from '../editor/Editor';
import Metadata from '../metadata-explorer/Explorer';
import { cn } from '../utils/cn';

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

const iconStyle = 'inline cursor-pointer h-5 w-5 ml-1 hover:text-primary-600';

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
          className={cn(
            'bg-white',
            showPanel ? 'flex flex-col flex-1 z-10 overflow-hidden' : '',
            vertical ? 'pt-2' : 'pl-2'
          )}
        >
          <div className={`relative flex`}>
            <Tabs
              options={[
                { label: 'Docs', id: 'docs', icon: DocumentTextIcon },
                { label: 'Metadata', id: 'metadata', icon: SparklesIcon },
              ]}
              initialSelection={selectedTab}
              onSelectionChange={handleSelectionChange}
              collapsedVertical={!vertical && !showPanel}
            />
            {/* Floating controls in top right corner */}
            {showPanel && (
              <div className="bg-white rounded-lg p-1 flex space-x-1 z-20 items-center">
                <ViewColumnsIcon
                  className={cn(iconStyle, !vertical ? 'rotate-90' : '')}
                  onClick={toggleOrientiation}
                  title="Toggle panel orientation"
                />
                <CollapseIcon
                  className={iconStyle}
                  onClick={toggleShowPanel}
                  title="Collapse panel"
                />
              </div>
            )}
          </div>
          {showPanel && (
            <div
              className={cn(
                'flex flex-1 mt-1',
                vertical ? 'overflow-auto' : 'overflow-hidden'
              )}
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
