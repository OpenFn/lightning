import {
  ChevronDownIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
  ChevronUpIcon,
  DocumentTextIcon,
  SparklesIcon,
  ViewColumnsIcon,
} from '@heroicons/react/24/outline';
import React, { useCallback, useMemo, useState } from 'react';
import Docs from '../../adaptor-docs/Docs';
import { Tabs } from '../../components/Tabs';
import Metadata from '../../metadata-explorer/Explorer';
import { useSession } from '../contexts/SessionProvider';
import { useWorkflowStore } from '../contexts/WorkflowStoreProvider';
import { CollaborativeMonaco } from './CollaborativeMonaco';

enum SettingsKeys {
  ORIENTATION = 'lightning.collaborative-job-editor.orientation',
  SHOW_PANEL = 'lightning.collaborative-job-editor.showPanel',
  ACTIVE_TAB = 'lightning.collaborative-job-editor.activeTab',
}

const persistedSettings = localStorage.getItem(
  'lightning.collaborative-job-editor.settings'
);
const settings = persistedSettings
  ? JSON.parse(persistedSettings)
  : {
      [SettingsKeys.ORIENTATION]: 'h',
      [SettingsKeys.SHOW_PANEL]: false,
    };

const persistSettings = () =>
  localStorage.setItem(
    'lightning.collaborative-job-editor.settings',
    JSON.stringify(settings)
  );

const iconStyle = 'inline cursor-pointer h-5 w-5 ml-1 hover:text-primary-600';

type CollaborativeJobEditorProps = {
  jobId: string;
  adaptor: string;
  disabled?: boolean;
  disabledMessage?: string;
  metadata?: object | true;
};

export const CollaborativeJobEditor: React.FC<CollaborativeJobEditorProps> = ({
  jobId,
  adaptor,
  disabled = false,
  disabledMessage,
  metadata,
}) => {
  const { awareness } = useSession();
  const { getJobBodyYText } = useWorkflowStore();

  const [vertical, setVertical] = useState(
    () => settings[SettingsKeys.ORIENTATION] === 'v'
  );
  const [showPanel, setShowPanel] = useState(
    () => settings[SettingsKeys.SHOW_PANEL]
  );
  const [selectedTab, setSelectedTab] = useState('docs');

  // Get Y.Text for this job from WorkflowStore
  const jobBodyYText = useMemo(() => {
    if (!jobId) return null;
    const ytext = getJobBodyYText(jobId);
    return ytext;
  }, [jobId, getJobBodyYText]);

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

  if (!jobBodyYText || !awareness) {
    return <div className="p-4">Loading collaborative editor...</div>;
  }

  return (
    <>
      <div className="cursor-pointer"></div>
      <div className={`flex h-full flex-${vertical ? 'col' : 'row'}`}>
        <div className="flex-1 rounded-md overflow-hidden">
          <CollaborativeMonaco
            ytext={jobBodyYText}
            awareness={awareness}
            adaptor={adaptor}
            disabled={disabled}
            className="h-full w-full"
          />
          {disabled && disabledMessage && (
            <div className="absolute inset-0 bg-gray-50 bg-opacity-90 flex items-center justify-center">
              <div className="bg-white p-4 rounded-lg shadow-lg">
                <p className="text-gray-700">{disabledMessage}</p>
              </div>
            </div>
          )}
        </div>
        <div
          className={`${
            showPanel ? 'flex flex-col flex-1 z-10 overflow-hidden' : ''
          } ${vertical ? 'pt-2' : 'pl-2'} bg-white`}
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
            )}
          </div>
          {showPanel && (
            <div
              className={`flex flex-1 mt-1 ${
                vertical ? 'overflow-auto' : 'overflow-hidden'
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
