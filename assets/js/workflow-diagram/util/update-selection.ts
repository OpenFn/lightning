// TODO: delete me

import { styleItem } from '../styles';
import type { Flow } from '../types';

/**
 * Handling selection change is kind of complex
 *
 * We have to reset the styles of the old selection
 * And update the styles of the new selection
 *
 * We can't use applyEdgeChanges because that doesn't allow you to
 * update styles
 *
 * TODO: as an optimisation, consider exiting early once we've updated both selected items
 */
export default (model: Flow.Model, newSelection: string | null) => {
  // let neighbours = {};

  // if (newSelection) {
  //   const selectedNode = model.nodes.find(n => n.id === newSelection);
  //   if (selectedNode) {
  //     neighbours = getConnectedEdges([selectedNode], model.edges).reduce(
  //       (obj, next) => {
  //         obj[next.id] = true;
  //         return obj;
  //       },
  //       {} as Record<string, true>
  //     );
  //   }
  // }

  const updatedModel = {
    nodes: model.nodes.map(updateItem) as Flow.Node[],
    // Must put selected edge LAST to ensure it stays on top.
    edges: model.edges.map(updateItem) as Flow.Edge[],
  };

  // we have no way of knowing whether the selection is a node or id
  // so we have to do both
  function updateItem(item: Flow.Edge | Flow.Node) {
    return styleItem({
      ...item,
      // data: { ...item.data, neighbour: item.id in neighbours },
      data: { ...item.data },
      selected: item.id === newSelection,
    });
  }

  return updatedModel;
};
