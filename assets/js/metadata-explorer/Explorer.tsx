import React, { useState, useCallback, useEffect } from 'react';

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
        <summary className="cursor-pointer">
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
}

export default ({ metadata }: MetadataExplorerProps) => {
  // const [filter, setFilter] = useState({ hideSystem: true });
  const [data, setData] = useState({ children: [] });

  const update = useCallback(() => {
    // const filtered = metadata.children.filter((e) => {
    //   // if (filter.hideSystem) {
    //   //   return !e.meta.system;
    //   // }
    //   return true;
    // })
    // console.log(filtered)
    // setData({ ...metadata, children: filtered });
    setData(metadata)
  }, [/*filter*/]);

  // This is SF specific so need to think about how we might drive this
  // const toggleSystem = useCallback((evt) => {
  //   const { checked } = evt.target;
  //   setFilter({ hideSystem: !checked });
  // });

  useEffect(() => update(), [/*filter*/])


  if (!metadata) {
    return <div>No metadata found</div>
  }
  
  return (
    <>
      {/* <p>
        <input type="checkbox" onChange={toggleSystem} />
        Show system children
      </p>
      <p>{data.children.length} children:</p> */}
      {map(data.children, data => <Entity level={0} data={data} />)}
    </>
  )
}