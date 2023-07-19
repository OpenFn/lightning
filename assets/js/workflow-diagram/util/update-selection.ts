import { styleItem } from '../styles';
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
export default (model: Flow.Model, newSelection: string) => {
  const updatedModel = {
    nodes: model.nodes.map(updateItem) as Flow.Node[],
    edges: model.edges.map(updateItem) as Flow.Edge[],
  };

  // we have no way of knowing whether the selection is a node or id
  // so we have to do both
  function updateItem(item: Flow.Edge | Flow.Node) {
    if (item.selected) {
      return styleItem({
        ...item,
        selected: false,
      });
    }
    if (item.id === newSelection) {
      return styleItem({
        ...item,
        selected: true,
      });
    }
    return item;
  }

  return updatedModel;
};
