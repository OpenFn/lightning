import type { ReactNode } from 'react';
import type { ModelNode } from './Model';

// utility to map the children of an Entity
// (which could be an object or array)
// to a function
const mapChildren = (model: ModelNode, fn: (child: ModelNode) => ReactNode) => {
  if (Array.isArray(model.children)) {
    return model.children.map(fn);
  }
  const obj = model.children as Record<string, ModelNode[]>;
  // if an object type, treat each key as an model
  return Object.keys(obj).map(key =>
    fn({
      name: key,
      // type: 'group',
      children: obj[key],
    } as ModelNode)
  );
};

export default mapChildren;
