import React from 'react';
import { ClockIcon, KeyIcon} from '@heroicons/react/24/outline';
import { InformationCircleIcon} from '@heroicons/react/24/solid';

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

const Label = ({ data }) => (<>
    <span className="inline-block align-bottom">{data.label || data.name}</span>
    {data.type && <span className="inline-block ml-4 mr-4 rounded-md border-secondary-300 text-slate-500 bg-sky-100/75 px-1 py-px cursor-default">{data.type}</span>}
</>)

const Entity = ({ data, level }) => {
  // TODO how do we render a description?
  if (hasChildren(data)) {
    // Best layout I can find for now - I'd really like the pills to be right-aligned
    return (
      <details>
        <summary className="text-sm text-secondary-700 mb-2 cursor-pointer marker:text-slate-600 marker:text-sm select-none whitespace-nowrap hover:bg-sky-50/50 pv-1">
          <Label data={data}/>
        </summary>
        <ul className="list-disc ml-4">
          {map(data.children, (e) => <Entity data={e} key={e.name} level={level + 1}  />)}
        </ul>
      </details>
    );
  }

  const indent = `ml-${level * 2}`;
  if (typeof data === 'string') {
    return (<li className={`text-sm text-secondary-700 whitespace-nowrap ${indent}`}>
      "{data}"
  </li>)
  }
  // TODO how do we drive formatting rules for adaptor specific types?
  return (<li className={`text-sm text-secondary-700 whitespace-nowrap ${indent}`}>
    <Label data={data}/>
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
        {/* TODO: make the icons break horizontally in large windows */}
        <p className="flex flex-row cursor-default" title={`This metadata was generated at ${metadata.created}`}>
          <ClockIcon className={iconStyle} />
          <span className="text-xs mb-1">{metadata.created}</span>
        </p>
        <p className="flex flex-row cursor-default" title="The credential used to generate metadata">
          <KeyIcon className={iconStyle} />
          <span className="text-xs mb-1">credential</span>
        </p>
        {/* TODO persist open state */}
        <details open>
          <summary className="block cursor-pointer text-sm">
            <InformationCircleIcon className={iconStyle + " inline"}/>
            <span className="font-bold">Help & Tips</span>
          </summary>
          <div className="border-slate-200 border-l-2 ml-2 pl-2" style={{ borderLeftWidth: '2px' }}>
            <p className="text-sm mb-2">Metadata shows you the structure of your datasource, based on your current credential.</p>
            <p className="text-sm mb-2">Press <pre className="inline text-xs">ctrl + space</pre> in the code editor for suggestions while writing code.</p>
          </div>
        </details>
        </div>
    </div>
  )
}