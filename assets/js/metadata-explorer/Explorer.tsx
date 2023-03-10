import React, { useState, useCallback, useEffect } from 'react';
import { ClockIcon, KeyIcon } from '@heroicons/react/24/outline'

const iconStyle = "h-4 w-4 text-grey-400 mr-1"

const hasChildren = ({ children } = {}) => {
  if (children) {
    if (Array.isArray(children)) {
      return children.length > 0;
    } else {
      return Object.keys(children).length > 0;
    }
  }
  return false;
}

// map over a list of children
const map = (children: any, fn: (child: any, index: any) => any) => {
  if (Array.isArray(children)) {
    return children.map(fn);
  }
  // if an object type, treat each key as an entity
  return Object.keys(children).map((key) => fn({
    name: key,
    // type: 'group',
    children: children[key],
  }));
}

const Entity = ({ data, level }) => {
  if (hasChildren(data)) {
    let label = data.label || data.name;
    if (data.type) {
      label += ` (${data.type})`;
    }
    return (
      <details>
        <summary className="text-sm text-secondary-700 mb-1 cursor-pointer marker:text-slate-600 marker:text-sm">
          {label}
        </summary>
        <ul className="list-disc ml-4">
          {map(data.children, (e) => <Entity data={e} key={e.name} level={level + 1}  />)}
        </ul>
      </details>
    );
  }

  const indent = `ml-${level * 2}`;
  if (typeof data === 'string') {
    return (<li className={`text-sm text-secondary-700 ${indent}`}>
      "{data}"
  </li>)
  }
  // TODO how do we drive formatting rules for adaptor specific types?
  return (<li className={`text-sm text-secondary-700 ${indent}`}>
    {data.name} {data.datatype && <i>({data.datatype})</i>} - {data.label}
  </li>)
}

type MetadataExplorerProps = {
  metadata?: any;
  adaptor?: string;
}

const Empty = ({ adaptor }: { adaptor: string }) => (<div>
  <p className="text-sm mb-4">{`No metadata found for ${adaptor}`}</p>
  <p  className="text-sm mb-4">This adaptor does not support magic functions yet.</p>
</div>)

export default ({ metadata, adaptor }: MetadataExplorerProps) => {
  if (!metadata) {
    return <Empty adaptor={adaptor} />
  }
  
  return (
    <div className="block flex-1 flex flex-col overflow-y-hidden">
      <div className="mt-2 flex-1 overflow-y-auto">
        {map(metadata.children, data => <Entity level={0} data={data} />)}
      </div>
      <div className="pt-4">
        <p className="text-sm mb-2">Metadata shows you the structure of your datasource, based on your current credential</p>
        <p className="flex flex-row cursor-default" title={`This metadata was generated at ${metadata.created}`}>
          <ClockIcon className={iconStyle} />
          <span className="text-xs mb-1">{metadata.created}</span>
        </p>
        <p className="flex flex-row cursor-default" title="The credential used to generate metadata">
          <KeyIcon className={iconStyle} />
          <span className="text-xs mb-1">credential</span>
        </p>
        </div>
    </div>
  )
}