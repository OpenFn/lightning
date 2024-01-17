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
      [SettingsKeys.SHOW_PANEL]: true,
    };

const persistSettings = () =>
  localStorage.setItem(
    'lightning.job-editor.settings',
    JSON.stringify(settings)
  );

const iconStyle = 'inline cursor-pointer h-6 w-6 mr-1 hover:text-primary-600';

type TabSpec = {
  label: string;
  id: string;
  icon: React.ComponentClass<React.SVGProps<SVGSVGElement>>;
};

type TabsProps = {
  options: TabSpec[];
  onSelectionChange?: (newName: string) => void;
  verticalCollapse: boolean;
  initialSelection?: String;
};

const Tabs = ({
  options,
  onSelectionChange,
  verticalCollapse,
  initialSelection,
}: TabsProps) => {
  const [selected, setSelected] = useState(initialSelection);

  const handleSelectionChange = (name: string) => {
    if (name !== selected) {
      setSelected(name);
      onSelectionChange?.(name);
    }
  };

  const commonStyle = 'flex';
  const horizStyle = 'flex-space-x-2 w-full';
  const vertStyle = 'flex-space-y-2';

  const style = verticalCollapse
    ? {
        writingMode: 'vertical-rl',
        textOrientation: 'mixed',
      }
    : {};

  return (
    <nav
      className={`${commonStyle} ${verticalCollapse ? vertStyle : horizStyle}`}
      aria-label="Tabs"
      style={style}
    >
      {options.map(({ label, id, icon }) => {
        const style =
          id === selected
            ? 'bg-primary-50 text-gray-700'
            : 'text-gray-400 hover:text-gray-700';
        return (
          <div
            key={id}
            onClick={() => handleSelectionChange(id)}
            className={`${style} select-none rounded-md px-3 py-2 text-sm font-medium cursor-pointer flex-row whitespace-nowrap`}
          >
            {React.createElement(icon, { className: iconStyle })}
            <span className="align-bottom">{label}</span>
          </div>
        );
      })}
    </nav>
  );
};

type JobEditorProps = {
  adaptor: string;
  source: string;
  disabled?: boolean;
  metadata?: object | true;
  onSourceChanged?: (src: string) => void;
};

export default ({
  adaptor,
  source,
  disabled,
  metadata,
  onSourceChanged,
}: JobEditorProps) => {
  const [vertical, setVertical] = useState(
    () => settings[SettingsKeys.ORIENTATION] === 'v'
  );
  const [showPanel, setShowPanel] = useState(
    () => settings[SettingsKeys.SHOW_PANEL]
  );
  const [selectedTab, setSelectedTab] = useState('docs');

  const toggleOrientiation = useCallback(() => {
    setVertical(!vertical);
    resize();
    settings[SettingsKeys.ORIENTATION] = vertical ? 'h' : 'v';
    persistSettings();
  }, [vertical]);

  const toggleShowPanel = useCallback(() => {
    setShowPanel(!showPanel);
    resize();
    settings[SettingsKeys.SHOW_PANEL] = !showPanel;
    persistSettings();
  }, [showPanel]);

  const handleSelectionChange = (newSelection: string) => {
    setSelectedTab(newSelection);
    if (!showPanel) {
      toggleShowPanel();
    }
  };

  // Force monaco editor to re-layout
  const resize = () => {
    setTimeout(() => {
      document.dispatchEvent(new Event('update-layout'));
    }, 2);
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
        <div className="flex-1 rounded-md border border-secondary-300 shadow-sm bg-vs-dark">
          <Editor
            source={source}
            adaptor={adaptor}
            metadata={metadata === true ? undefined : metadata}
            disabled={disabled}
            onChange={onSourceChanged}
          />
        </div>
        <div
          className={`${
            showPanel ? 'flex flex-1 flex-col z-10 overflow-auto' : ''
          } bg-white`}
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
              vertical ? 'pt-2' : 'pl-2',
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
              className={`flex select-none flex-1 text-right py-2 ${
                !showPanel && !vertical ? 'px-2 flex-col-reverse' : 'flex-row'
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
              className={`flex flex-1 ${
                vertical ? 'overflow-auto' : 'overflow-hidden'
              } px-2`}
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
