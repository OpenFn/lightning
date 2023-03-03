import React, { useState, useCallback, useMemo } from 'react';
import { ViewColumnsIcon, ChevronLeftIcon, ChevronRightIcon, ChevronUpIcon, ChevronDownIcon } from '@heroicons/react/24/outline'

import Editor from '../editor/Editor';

const iconStyle = "cursor-pointer h-6 w-6"

export default ({ adaptor, source }) => {
  const [vertical, setVertical] = useState(true);
  const [showPanel, setShowPanel] = useState(true);

  const toggleOrientiation = useCallback(() => {
    setVertical(!vertical)
    resize();
  }, [vertical])

  const toggleShowPanel = useCallback(() => {
    setShowPanel(!showPanel)
    resize();
  }, [showPanel])

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

  return (<>
  <div className="cursor-pointer" >
  </div>
  <div className={`flex h-full v-full flex-${vertical ? 'col' : 'row'}`}>
    <div className="flex flex-1 rounded-md border border-secondary-300 shadow-sm bg-vs-dark">
      {/* TODO need this to resize nicely dynamically */}
      <Editor source={source} adaptor={adaptor} />
    </div>
    <div className={`${showPanel ? 'flex flex-col flex-1' : ''} bg-white`}>
      <div className={`flex flex-${!vertical && !showPanel ? 'col' : 'row'} text-right`}>
        <ViewColumnsIcon className={iconStyle} onClick={toggleOrientiation} />
        <CollapseIcon className={iconStyle} onClick={toggleShowPanel} />
      </div>
      {showPanel && 
        <div className="h-full v-full bg-slate-300">
          panel
        </div>
      }
    </div>
  </div>
  </>)
}