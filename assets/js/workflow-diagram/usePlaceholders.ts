/*
 * Hook for placeholder management
 */
import { useState, useCallback, useEffect } from 'react';
import { useStore, StoreApi } from 'zustand';

import { styleEdge } from './styles';
import { Flow } from './types';
import toWorkflow from './util/to-workflow';
import type { WorkflowState } from '../workflow-editor/store';
import { DEFAULT_TEXT } from '../editor/Editor';

// generates a placeholder node and edge as child of the parent
export const create = (parentNode: Flow.Node) => {
  const newModel: Flow.Model = {
    nodes: [],
    edges: [],
  };

  const targetId = crypto.randomUUID();
  newModel.nodes.push({
    id: targetId,
    type: 'placeholder',
    position: {
      // Offset the position of the placeholder to be more pleasing during animation
      x: parentNode.position.x,
      y: parentNode.position.y + 100,
    },
    data: {
      body: DEFAULT_TEXT,
      adaptor: '@openfn/language-common@latest',
    },
  });

  newModel.edges.push(
    styleEdge({
      id: crypto.randomUUID(),
      type: 'step',
      source: parentNode.id,
      target: targetId,
      data: { condition_type: 'on_job_success', placeholder: true },
    })
  );

  return newModel;
};

export default (
  ref: HTMLElement | null,
  store: StoreApi<WorkflowState>,
  requestSelectionChange: (id: string | null) => void // TODO more like changeSelection
) => {
  // TODO in new-workflow, we need to take a placeholder as a prop
  const [placeholders, setPlaceholders] = useState<Flow.Model>({
    nodes: [],
    edges: [],
  });

  const addToStore = useStore(store!, state => state.add);

  const add = useCallback((parentNode: Flow.Node) => {
    // Generate a placeholder node and edge
    const updated = create(parentNode);
    setPlaceholders(updated);

    requestSelectionChange(updated.nodes[0].id);
  }, []);

  const commit = useCallback(
    (evt: CustomEvent<any>) => {
      const { id, name } = evt.detail;

      // reset the chart
      setPlaceholders({ nodes: [], edges: [] });

      // Update the store
      placeholders.nodes[0].data.name = name;
      addToStore(toWorkflow(placeholders));

      requestSelectionChange(id);
    },
    [addToStore, placeholders]
  );

  const cancel = useCallback((_evt?: CustomEvent<any>) => {
    setPlaceholders({ nodes: [], edges: [] });
  }, []);

  useEffect(() => {
    if (ref) {
      ref.addEventListener<any>('commit-placeholder', commit);
      ref.addEventListener<any>('cancel-placeholder', cancel);

      return () => {
        if (ref) {
          ref.removeEventListener<any>('commit-placeholder', commit);
          ref.removeEventListener<any>('cancel-placeholder', cancel);
        }
      };
    }
  }, [commit, cancel, ref]);

  return { placeholders, add, cancel };
};
