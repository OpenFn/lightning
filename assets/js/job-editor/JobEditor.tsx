import React, { useState, useCallback } from 'react';

export default () => {
  const [vertical, setVertical] = useState(true);
  const [showPanel, setShowPanel] = useState(true);

  const toggleOrientiation = useCallback(() => {
    setVertical(!vertical)
  }, [vertical])

  const toggleShowPanel = useCallback(() => {
    setShowPanel(!showPanel)
  }, [showPanel])

  return (<>
  <div className="cursor-pointer" onClick={toggleOrientiation}>toggle</div>
  <div className={`flex h-full v-full flex-${vertical ? 'col' : 'row'}`}>
    <div className="flex flex-1 bg-slate-100">editor</div>
    <div className={`${showPanel ? 'flex flex-col flex-1' : ''} bg-white`}>
      <div className="cursor-pointer float-right" onClick={toggleShowPanel}>
        {'<>'}
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