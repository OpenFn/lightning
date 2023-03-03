import React, { useState, useCallback, useMemo, useEffect } from 'react';
import { ViewColumnsIcon, ChevronLeftIcon, ChevronRightIcon, ChevronUpIcon, ChevronDownIcon } from '@heroicons/react/24/outline'

import Docs from '../adaptor-docs/Docs';
import Editor from '../editor/Editor';
import Metadata from '../metadata-explorer/Explorer';
import loadMetadata from '../metadata-loader/metadata';

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
          return <div onClick={() => handleSelectionChange(name)} className={`${style} rounded-md px-3 py-2 text-sm font-medium cursor-pointer`}>{name}</div>
        })
      }
    </nav>
  )
}

export default ({ adaptor, source }) => {
  const [vertical, setVertical] = useState(false);
  const [showPanel, setShowPanel] = useState(true);
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
  }, [vertical])

  const toggleShowPanel = useCallback(() => {
    setShowPanel(!showPanel)
    resize();
  }, [showPanel])

  const handleSelectionChange = (newSelection: string) => {
    setSelectedTab(newSelection);
    if (!showPanel) {
      setShowPanel(true);
      resize();
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
      <Editor source={source} adaptor={adaptor} metadata={metadata} />
    </div>
    <div className={`${showPanel ? 'flex flex-col flex-1' : ''} bg-white ${vertical && 'overflow-auto'}`}>
      <div className={`flex flex-${!vertical && !showPanel ? 'col-reverse items-center' : 'row'} w-full justify-items-end sticky`}>
        <Tabs options={['Docs', 'Metadata']} onSelectionChange={handleSelectionChange} verticalCollapse={!vertical && !showPanel} />
        <ViewColumnsIcon className={iconStyle} onClick={toggleOrientiation} />
        <CollapseIcon className={iconStyle} onClick={toggleShowPanel} />
      </div>
      {showPanel && 
        <div className={`h-full v-full ${!vertical && 'overflow-auto' || ''} px-2`}>
          {/* TODO ideally we wouldn't re-render the component from scratch? */}
          {selectedTab === 'Docs' && <Docs adaptor={adaptor} />}
          {selectedTab === 'Metadata' && <Metadata metadata={metadata} />}
        </div>
      }
    </div>
  </div>
  </>)
}