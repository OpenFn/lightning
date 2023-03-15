import React from 'react';
import mapChildren from './map-children';
import type { ModelNode } from './Model'

type EntityProps = {
  level: number;
  data: ModelNode;
}

const summaryStyle = "text-sm text-secondary-700 mb-1 marker:text-slate-600 marker:text-sm select-none whitespace-nowrap hover:bg-sky-50/50";

const hasChildren = ({ children }: Partial<ModelNode> = {}) => {
  if (children) {
    if (Array.isArray(children)) {
      return children.length > 0;
    } else {
      return Object.keys(children).length > 0;
    }
  }
  return false;
}

const Label = ({ data }: { data: ModelNode }) => (<>
  {data.label && data.name && 
    <>
      <span className="inline-block align-bottom">{data.label}</span>
      <pre className="inline text-xs align-bottom font-monospace ml-2">({data.name})</pre>
    </>
  }
  {!data.label && data.name && 
    <span className="inline-block align-bottom">{data.name}</span>
  }
  {data.type && <span className="inline-block ml-4 mr-4 rounded-md border-secondary-300 text-slate-500 bg-sky-100/75 px-1 py-px cursor-default">{data.type}</span>}
</>)

// Renders a model entity
const Entity = ({ data, level }: EntityProps) => {
  // TODO how do we render a description?
  if (hasChildren(data)) {
    // Best layout I can find for now - I'd really like the pills to be neatly right-aligned without scrolling
    return (
      <details>
        <summary className={`${summaryStyle} cursor-pointer`}>
          <Label data={data}/>
        </summary>
        <ul className="list-disc ml-4">
          {mapChildren(data, (e) => <Entity data={e} key={e.name} level={level + 1}  />)}
        </ul>
      </details>
    );
  }

  const indent = `ml-${level * 2}`;
  if (typeof data === 'string') {
    return (<li className={`${summaryStyle} cursor-default ${indent}`}>
      "{data}"
  </li>)
  }
  // TODO how do we drive formatting rules for adaptor specific types?
  return (<li className={`${summaryStyle} cursor-default ${indent}`}>
    <Label data={data}/>
  </li>)
}

export default Entity;