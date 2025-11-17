/*
 * Hook for placeholder management
 */
import type { XYPosition } from '@xyflow/react';
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
  where?: XYPosition,
  adaptor?: string
) => {
  const newModel: Flow.Model = {
    nodes: [],
    edges: [],
  };

  const targetId = randomUUID();
  newModel.nodes.push({
    id: targetId,
    type: 'placeholder',
    position: {
      // mark this as as default position
      // @ts-ignore _default is a temporary flag added by us
      _default: true,

      // Offset the position of the placeholder to be more pleasing during animation
      // subtract 55 because there's a magic number at PlaceholderJob.tsx:137 which is 35px. it takes us 35px to the right of. so we calculate the rest of the half
      x: where?.x ? where.x - 55 : parentNode.position.x,
      // subtract 20 because that's the half of placeholder height
      y: where?.y ? where.y - 20 : parentNode.position.y + 120,
    },
    data: {
      body: DEFAULT_TEXT,
      adaptor: adaptor || '@openfn/language-common@latest',
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

export default (
  el: HTMLElement | null | undefined,
  isManualLayout: boolean = false,
  requestSelectionChange: (id: string | null) => void // TODO more like changeSelection
) => {
  const { add: addTo } = useWorkflowStore();
  // TODO in new-workflow, we need to take a placeholder as a prop
  const [placeholders, setPlaceholders] = useState<Flow.Model>({
    nodes: [],
    edges: [],
  });

  // for updating placeholder position
  const updatePlaceholderPosition = useCallback(
    (nodeId: string, position: XYPosition) => {
      setPlaceholders(prev => ({
        ...prev,
        nodes: prev.nodes.map(n => {
          if (n.id === nodeId) return { ...n, position };
          else return n;
        }),
      }));
    },
    []
  );

  const add = useCallback(
    (parentNode: Flow.Node, where?: XYPosition, adaptor?: string) => {
      // Generate a placeholder node and edge
      const updated = create(parentNode, where, adaptor);
      setPlaceholders(updated);

      requestSelectionChange(updated.nodes[0].id);
    },
    []
  );

  const commit = useCallback(
    (evt: CustomEvent<any>) => {
      const { id, name } = evt.detail;

      // reset the chart
      setPlaceholders({ nodes: [], edges: [] });

      // Update the store
      placeholders.nodes[0].data.name = name;
      // we need to pass isManualLayout to tell toWorkflow to process position information
      addTo(toWorkflow(placeholders, isManualLayout));

      requestSelectionChange(id);
    },
    [placeholders]
  );

  const cancel = useCallback((_evt?: CustomEvent<any>) => {
    setPlaceholders({ nodes: [], edges: [] });
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

  return { placeholders, add, cancel, updatePlaceholderPosition };
};
