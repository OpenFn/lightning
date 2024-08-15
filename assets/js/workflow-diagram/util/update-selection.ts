import { getConnectedEdges } from 'reactflow';
import { sortOrderForSvg, styleItem } from '../styles';
import { Flow } from '../types';

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
  let neighbours = {};

  if (newSelection) {
    const selectedNode = model.nodes.find(n => n.id === newSelection);
    if (selectedNode) {
      console.log(selectedNode);

      neighbours = getConnectedEdges([selectedNode], model.edges).reduce(
        (obj, next) => {
          obj[next.id] = true;
          return obj;
        },
        {}
      );
    }
  }

  const updatedModel = {
    nodes: model.nodes.map(updateItem) as Flow.Node[],
    // Must put selected edge LAST to ensure it stays on top.
    edges: model.edges.map(updateItem).sort(sortOrderForSvg) as Flow.Edge[],
  };

  // we have no way of knowing whether the selection is a node or id
  // so we have to do both
  function updateItem(item: Flow.Edge | Flow.Node) {
    return styleItem({
      ...item,

      // using the selection flag for neighbouring edges is SO much easier (and clearer)
      selected: item.id === newSelection || item.id in neighbours,
      // // @ts-ignore
      // neighbour: item.id in neighbours,
    });
  }

  return updatedModel;
};
