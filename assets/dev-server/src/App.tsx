import React from 'react';

import WorkflowDiagram from '../../js/workflow-diagram/src/index'

import './main.css'

export default () => {
  return (<div className="flex flex-row h-full w-full">
    <div className="flex-1 border-2 border-slate-200 m-2 ">
      <WorkflowDiagram  />
    </div>
    <div className="flex-1 flex flex-col h-full w-1/3">
      <div className="flex-1 border-2 border-slate-200 m-2">Drill down</div>
      <div className="flex-1 border-2 border-slate-200 m-2">Changes</div>
    </div>
  </div>
  );
};

/*
  I think the app needs to create the store and pass it in

  How do I get tailwind in here?


  How do I import the workflow diagram styles properly?

*/