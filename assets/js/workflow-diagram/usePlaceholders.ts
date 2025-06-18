/*
 * Hook for placeholder management
 */
import { useCallback, useEffect, useState } from 'react';

import { randomUUID } from '../common';
import { DEFAULT_TEXT } from '../editor/Editor';
import { useWorkflowStore } from '../workflow-store/store';
import { styleEdge } from './styles';
import type { Flow } from './types';
import toWorkflow from './util/to-workflow';

// generates a placeholder node and edge as child of the parent
export const create = (
  parentNode: Flow.Node,
  position?: { x: number; y: number }
) => {
  const newModel: Flow.Model = {
    nodes: [],
    edges: [],
  };

  const targetId = randomUUID();
  newModel.nodes.push({
    id: targetId,
    type: 'placeholder',
    width: 350, // Set initial dimensions to prevent flicker
    height: 200, // Set initial dimensions to prevent flicker
    position: {
      // mark this as as default position
      // @ts-ignore _default is a temporary flag added by us
      _default: true,
      // Offset the position of the placeholder to be more pleasing during animation
      x: position?.x ?? parentNode.position.x,
      y: position?.y ?? parentNode.position.y + 100,
    },
    data: {
      body: DEFAULT_TEXT,
      adaptor: '@openfn/language-common@latest',
    },
  });

  newModel.edges.push(
    styleEdge({
      id: randomUUID(),
      type: 'step',
      source: parentNode.id,
      target: targetId,
      data: { condition_type: 'on_job_success', placeholder: true },
    })
  );

  return newModel;
};

const reset_data = { nodes: [], edges: [] };

export default (
  el: HTMLElement | null | undefined,
  requestSelectionChange: (id: string | null) => void, // TODO more like changeSelection
  renderWithPlaceHolder: (placeholders: Flow.Model) => void
) => {
  const { add: addTo } = useWorkflowStore();
  // TODO in new-workflow, we need to take a placeholder as a prop
  const [placeholders, setPlaceholders] = useState<Flow.Model>({
    nodes: [],
    edges: [],
  });

  const add = useCallback(
    (parentNode: Flow.Node, position?: { x: number; y: number }) => {
      // Generate a placeholder node and edge
      const updated = create(parentNode, position);
      setPlaceholders(updated);
      // call for a render with this placeholder
      renderWithPlaceHolder(updated);

      // request the placeholder is selected
      requestSelectionChange(updated.nodes[0].id);
    },
    []
  );

  const commit = useCallback(
    (evt: CustomEvent<any>) => {
      const { id, name } = evt.detail;

      // update the single placeholder in state with a name
      placeholders.nodes[0].data.name = name;
      placeholders.nodes[0].id = id; // hmmm

      // commit this placeholder to the store
      const modelWithPlaceholder = toWorkflow(placeholders);
      addTo(modelWithPlaceholder);

      // clear placeholder state after it's been commited to the store.
      setPlaceholders(reset_data);

      // request that this newly created node is selected
      requestSelectionChange(id);
    },
    [placeholders]
  );

  const cancel = useCallback((_evt?: CustomEvent<any>) => {
    setPlaceholders(reset_data);
    renderWithPlaceHolder(reset_data);
  }, []);

  useEffect(() => {
    if (el) {
      el.addEventListener<any>('commit-placeholder', commit);
      el.addEventListener<any>('cancel-placeholder', cancel);

      return () => {
        if (el) {
          el.removeEventListener<any>('commit-placeholder', commit);
          el.removeEventListener<any>('cancel-placeholder', cancel);
        }
      };
    }
  }, [commit, cancel, el]);

  return { placeholders, add, cancel };
};
