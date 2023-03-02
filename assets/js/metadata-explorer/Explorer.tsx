import React, { useState, useCallback, useEffect } from 'react';

const Group = ({ data, level }) => {
  return (<ul className="list-inside list-disc">{
    data.children.map((e) => <Entity data={e} key={e.name} level={level}  />
  )}
  </ul>)
}

const Entity = ({ data, level }) => {
  const indent = `ml-${level * 2}`;
  return <li className={`text-sm text-secondary-700 mt-1 ${indent}`}>
    <span>
      {data.name}
      {data.datatype && <i>({data.datatype})</i>}
    </span>
    {data.children && 
      <Group data={data} level={level + 1} />
    }
  </li>
}

type MetadataExplorerProps = {
  metadata: any;
}

export default ({ metadata }: MetadataExplorerProps) => {
  console.log(metadata)
  // const [filter, setFilter] = useState({ hideSystem: true });
  const [data, setData] = useState({ children: [] });

  const update = useCallback(() => {
    const filtered = metadata.children.filter((e) => {
      // if (filter.hideSystem) {
      //   return !e.meta.system;
      // }
      return true;
    })
    console.log(filtered)
    setData({ ...metadata, children: filtered });
  }, [/*filter*/]);

  // This is SF specific so need to think about how we might drive this
  // const toggleSystem = useCallback((evt) => {
  //   const { checked } = evt.target;
  //   setFilter({ hideSystem: !checked });
  // });

  useEffect(() => update(), [/*filter*/])
  
  return (
    <>
      <h1>Metadata Explorer</h1>
      {/* <p>
        <input type="checkbox" onChange={toggleSystem} />
        Show system children
      </p>
      <p>{data.children.length} children:</p> */}
      <Group level={0} data={data} />
    </>
  )
}