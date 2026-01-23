import {
  applyNodeChanges,
  Background,
  ControlButton,
  Controls,
  MiniMap,
  type NodeChange,
  ReactFlow,
  useReactFlow,
} from '@xyflow/react';
import React, { useCallback, useEffect, useRef, useState } from 'react';
import tippy from 'tippy.js';

import { useProjectAdaptors } from '#/collaborative-editor/hooks/useAdaptors';
import useConnect from '#/collaborative-editor/hooks/useConnect';
import {
  usePositions,
  useWorkflowReadOnly,
  useWorkflowState,
  useWorkflowStoreContext,
} from '#/collaborative-editor/hooks/useWorkflow';
import type { Workflow } from '#/collaborative-editor/types/workflow';
import { getAdaptorDisplayName } from '#/collaborative-editor/utils/adaptorUtils';
import debounce from '#/collaborative-editor/utils/debounce';
import { isSourceNodeJob } from '#/collaborative-editor/utils/workflowGraph';
import { randomUUID } from '#/common';
import _logger from '#/utils/logger';
import MiniMapNode from '#/workflow-diagram/components/MiniMapNode';
import { FIT_DURATION, FIT_PADDING } from '#/workflow-diagram/constants';
import edgeTypes from '#/workflow-diagram/edges';
import layout from '#/workflow-diagram/layout';
import nodeTypes from '#/workflow-diagram/nodes';
import type { Flow, Positions } from '#/workflow-diagram/types';
import usePlaceholders from '#/workflow-diagram/usePlaceholders';
import { ensureNodePosition } from '#/workflow-diagram/util/ensure-node-position';
import fromWorkflow from '#/workflow-diagram/util/from-workflow';
import shouldLayout from '#/workflow-diagram/util/should-layout';
import updateSelectionStyles from '#/workflow-diagram/util/update-selection';
import {
  getVisibleRect,
  isPointInRect,
} from '#/workflow-diagram/util/viewport';
import type { RunInfo } from '#/workflow-store/store';

import { createEmptyRunInfo } from '../../utils/runStepsTransformer';
import { AdaptorSelectionModal } from '../AdaptorSelectionModal';

import { PointerTrackerViewer } from './PointerTrackerViewer';
import flowHandlers from './react-flow-handlers';

type WorkflowDiagramProps = {
  el?: HTMLElement | null;
  containerEl: HTMLElement;
  selection: string | null;
  onSelectionChange: (id: string | null) => void;
  showAiAssistant?: boolean;
  aiAssistantId?: string;
  showInspector?: boolean;
  inspectorId?: string | undefined;
  layoutDuration?: number;
  runSteps?: RunInfo | null;
};

type ChartCache = {
  positions: Positions;
  lastSelection: string | null;
  lastLayout?: string | undefined;
  layoutDuration?: number;
};

const LAYOUT_DURATION = 300;

// Simple React hook for Tippy tooltips that finds buttons by their content
const useTippyForControls = (
  isManualLayout: boolean,
  canUndo: boolean,
  canRedo: boolean
) => {
  useEffect(() => {
    // Find the control buttons and initialize tooltips based on their dataset attributes
    const buttons = document.querySelectorAll('.react-flow__controls button');

    const cleaner: (() => void)[] = [];
    buttons.forEach(button => {
      if (button instanceof HTMLElement && button.dataset['tooltip']) {
        const tp = tippy(button, {
          content: button.dataset['tooltip'],
          placement: 'right',
          animation: false,
          allowHTML: false,
        });
        cleaner.push(tp.destroy.bind(tp));
      }
    });

    return () => {
      cleaner.forEach(f => {
        f();
      });
    };
  }, [isManualLayout, canUndo, canRedo]);
};

// increase this value to determine the amount of movement we allow during a click
const DRAG_THRESHOLD = 2;

const logger = _logger.ns('WorkflowDiagram').seal();
const flowhandlers = flowHandlers({ dragThreshold: DRAG_THRESHOLD });

export default function WorkflowDiagram(props: WorkflowDiagramProps) {
  const flow = useReactFlow();
  // value of select in props seems same as select in store.
  // one in props is always set on initial render. (helps with refresh)
  const { selection, onSelectionChange, containerEl: el, runSteps } = props;

  const workflowStore = useWorkflowStoreContext();

  // Get workflow actions including position updates
  const {
    positions: workflowPositions,
    updatePosition,
    updatePositions,
  } = usePositions();

  // Undo/redo functions
  const undo = useCallback(() => {
    workflowStore.undo();
  }, [workflowStore]);

  const redo = useCallback(() => {
    workflowStore.redo();
  }, [workflowStore]);

  const { jobs, triggers, edges } = useWorkflowState(state => ({
    jobs: state.jobs,
    triggers: state.triggers,
    edges: state.edges,
  }));

  const { isReadOnly } = useWorkflowReadOnly();

  const workflow = React.useMemo(() => {
    // Entities already have errors denormalized from store
    return {
      jobs,
      triggers,
      edges,
      disabled: isReadOnly,
    };
  }, [jobs, triggers, edges, isReadOnly]);

  const isManualLayout = Object.keys(workflowPositions).length > 0;

  const [model, setModel] = useState<Flow.Model>({ nodes: [], edges: [] });

  const [drawerWidth, setDrawerWidth] = useState(0);
  const workflowDiagramRef = useRef<HTMLDivElement>(null);

  // Undo/redo state
  const [canUndo, setCanUndo] = useState(false);
  const [canRedo, setCanRedo] = useState(false);

  const undoManager = workflowStore.getSnapshot().undoManager;

  // Listen to UndoManager stack changes
  useEffect(() => {
    if (!undoManager) {
      setCanUndo(false);
      setCanRedo(false);
      return;
    }

    const updateUndoRedoState = () => {
      // Read directly from undoManager instead of calling store methods
      // This avoids potential stale closures and is more reliable
      setCanUndo(undoManager.undoStack.length > 0);
      setCanRedo(undoManager.redoStack.length > 0);
    };

    // Initial state
    updateUndoRedoState();

    // Listen to stack changes
    undoManager.on('stack-item-added', updateUndoRedoState);
    undoManager.on('stack-item-popped', updateUndoRedoState);
    undoManager.on('stack-cleared', updateUndoRedoState);

    return () => {
      undoManager.off('stack-item-added', updateUndoRedoState);
      undoManager.off('stack-item-popped', updateUndoRedoState);
      undoManager.off('stack-cleared', updateUndoRedoState);
    };
  }, [undoManager]);

  // Modal state for adaptor selection
  const [pendingPlaceholder, setPendingPlaceholder] = useState<{
    sourceNode: Flow.Node;
    position: { x: number; y: number };
  } | null>(null);

  // Fetch project adaptors for modal
  const { projectAdaptors } = useProjectAdaptors();

  const updateSelection = useCallback(
    (id?: string | null) => {
      id = id || null;

      chartCache.current.lastSelection = id;
      onSelectionChange(id);
    },
    [onSelectionChange]
  );

  // selection can be null give 2 events
  // 1. we click empty space on editor (client event)
  // 2. selection prop becomes null (server event)
  // on option 2. chartCache isn't updated. Hence we call updateSelection to do that
  useEffect(() => {
    // we know selection from server has changed when it's not equal to the one on client
    if (selection !== chartCache.current.lastSelection)
      updateSelection(selection);
  }, [selection, updateSelection]);

  const {
    placeholders,
    add: _addPlaceholder,
    cancel: cancelPlaceholder,
    updatePlaceholderPosition,
  } = usePlaceholders(el, isManualLayout, updateSelection);

  // Override the placeholder commit handler to use Y.Doc store
  useEffect(() => {
    if (!el) return;

    const handleCommit = (evt: CustomEvent) => {
      // Stop event propagation to prevent old workflow store handler
      // from firing. The old handler (from usePlaceholders.ts) tries to send
      // push-change to LiveView which doesn't exist in collaborative mode.
      evt.stopImmediatePropagation();

      const { id, name } = evt.detail;

      // Get placeholder data
      const placeholderNode = placeholders.nodes[0];
      const placeholderEdge = placeholders.edges[0];

      if (!placeholderNode) return;

      // Cast data to access placeholder-specific properties
      const nodeData = placeholderNode.data as any;

      // Create job data for Y.Doc
      const newJob = {
        id,
        name,
        body: nodeData.body as string,
        adaptor: nodeData.adaptor as string,
      };

      // Add to Y.Doc store
      workflowStore.addJob(newJob);

      // Handle position for manual layout mode
      if (isManualLayout) {
        workflowStore.updatePosition(id, placeholderNode.position);
      }

      // Create edge if placeholder has one
      if (placeholderEdge) {
        // TODO: This edge creation logic is duplicated in useConnect.ts
        // (onConnect callback). Consider extracting to a shared helper like
        // createEdgeForSource() to avoid inconsistencies.
        const edgeData = placeholderEdge.data as any;

        // Determine if source is a job or trigger by checking the workflow state
        const sourceIsJob = isSourceNodeJob(placeholderEdge.source, jobs);

        const newEdge: Record<string, any> = {
          id: placeholderEdge.id,
          target_job_id: id,
          condition_type: edgeData?.condition_type || 'on_job_success',
          enabled: true,
        };

        // Set either source_job_id or source_trigger_id
        if (sourceIsJob) {
          newEdge['source_job_id'] = placeholderEdge.source;
          newEdge['source_trigger_id'] = null;
        } else {
          newEdge['source_job_id'] = null;
          newEdge['source_trigger_id'] = placeholderEdge.source;
        }

        workflowStore.addEdge(newEdge);
      }

      // Clear placeholder AFTER Y.Doc updates
      // Y.Doc transactions are synchronous, so the store state is already
      // updated. Canvas will re-render with new job before placeholder is
      // cleared, preventing blank canvas during race conditions.
      cancelPlaceholder();

      // Select the new job
      updateSelection(id);
    };

    // Attach our custom commit handler in capture phase
    // This ensures it fires BEFORE the old handler from usePlaceholders.ts
    // We call stopImmediatePropagation() to prevent the old handler from executing
    el.addEventListener('commit-placeholder' as any, handleCommit, true);

    return () => {
      el.removeEventListener('commit-placeholder' as any, handleCommit, true);
    };
  }, [
    el,
    placeholders,
    isManualLayout,
    workflowStore,
    updateSelection,
    jobs,
    cancelPlaceholder,
  ]);

  // Track positions and selection on a ref, as a passive cache, to prevent re-renders
  const chartCache = useRef<ChartCache>({
    positions: {},
    // This will set the initial selection into the cache
    lastSelection: selection,
    lastLayout: undefined,
  });

  const forceLayout = useCallback(async () => {
    if (!flow) return Promise.resolve({});

    const viewBounds = {
      width: workflowDiagramRef.current?.clientWidth ?? 0,
      height: workflowDiagramRef.current?.clientHeight ?? 0,
    };
    const positions = await layout(model, setModel, flow, viewBounds, {
      duration: props.layoutDuration ?? LAYOUT_DURATION,
      forceFit: false,
    });
    // Note we don't update positions until the animation has finished
    chartCache.current.positions = positions;
    if (isManualLayout) updatePositions(positions);
    return positions;
  }, [flow, model, isManualLayout, updatePositions, props.layoutDuration]);

  // Respond to changes pushed into the component from outside
  // This usually means the workflow has changed or its the first load, so we don't want to animate
  // Later, if responding to changes from other users live, we may want to animate
  useEffect(() => {
    logger.debug('main useEffect triggered', {
      jobCount: workflow.jobs.length,
      triggerCount: workflow.triggers.length,
      edgeCount: workflow.edges.length,
      workflowPositionsCount: Object.keys(workflowPositions).length,
      cachedPositionsCount: Object.keys(chartCache.current.positions).length,
      isManualLayout,
      hasFlow: !!flow,
    });

    // Don't update model until ReactFlow is initialized
    // This prevents visual artifacts during version switches where nodes
    // would flash at position (0,0) before ReactFlow is ready
    if (!flow) {
      logger.debug('flow not initialized yet, skipping model update');
      return;
    }

    // Clear cache if positions were cleared (e.g., after reset workflow)
    // This prevents stale cached positions from being used when Y.Doc positions are empty
    // Also clear lastLayout so shouldLayout() will trigger a new layout
    if (
      Object.keys(workflowPositions).length === 0 &&
      Object.keys(chartCache.current.positions).length > 0
    ) {
      logger.debug('clearing cached positions');
      chartCache.current.positions = {};
      chartCache.current.lastLayout = undefined;
    }

    const { positions } = chartCache.current;

    // Fix: If positions are empty but lastLayout is set, clear lastLayout to force layout
    // This can happen when cache gets out of sync (e.g., after page refresh in auto-layout mode)
    if (Object.keys(positions).length === 0 && chartCache.current.lastLayout) {
      chartCache.current.lastLayout = undefined;
    }

    // create model from workflow and also apply selection styling to the model.
    const newModel = updateSelectionStyles(
      fromWorkflow(
        workflow,
        positions,
        placeholders,
        runSteps || createEmptyRunInfo(),
        // Use current selection prop, not cached lastSelection
        // This ensures URL changes (from Header Run button) highlight nodes
        selection
      ),
      selection
    );

    logger.debug('fromWorkflow result', {
      nodeCount: newModel.nodes.length,
      edgeCount: newModel.edges.length,
      nodeIds: newModel.nodes.map(n => n.id),
      hasPositions: newModel.nodes.map(n => ({
        id: n.id,
        hasPos: !!n.position,
      })),
    });
    if (newModel.nodes.length > 0) {
      // If defaulting positions for multiple nodes,
      // try to offset them a bit
      const positionOffsetMap: Record<string, number> = {};

      // We have nodes - process layout and render
      if (flow) {
        const layoutId = shouldLayout(
          newModel.edges,
          newModel.nodes,
          isManualLayout,
          chartCache.current.lastLayout
        );

        logger.debug('shouldLayout decision', {
          layoutId,
          lastLayout: chartCache.current.lastLayout,
          isManualLayout,
          willLayout: !!layoutId,
        });

        if (layoutId) {
          chartCache.current.lastLayout = layoutId;
          const viewBounds = {
            width: workflowDiagramRef.current?.clientWidth ?? 0,
            height: workflowDiagramRef.current?.clientHeight ?? 0,
          };
          logger.debug('layout triggered', {
            layoutId,
            isManualLayout,
            viewBounds,
            nodeCount: newModel.nodes.length,
          });

          if (isManualLayout) {
            // give nodes positions
            const nodesWPos = newModel.nodes.map(node => {
              // during manualLayout. a placeholder wouldn't have position in
              // positions in store hence use the position on the placeholder
              // node
              const isPlaceholder = node.type === 'placeholder';

              const newNode = {
                ...node,
                position: isPlaceholder
                  ? node.position
                  : workflowPositions[node.id],
              };
              ensureNodePosition(
                newModel,
                { ...positions, ...workflowPositions },
                newNode,
                positionOffsetMap
              );
              return newNode;
            });
            setModel({ ...newModel, nodes: nodesWPos });
            chartCache.current.positions = workflowPositions;
            logger.debug('manual layout: applied positions from store', {
              positionCount: Object.keys(workflowPositions).length,
            });
          } else {
            logger.debug('auto layout: calling layout()', {
              nodePositions: newModel.nodes.map(n => ({
                id: n.id,
                pos: n.position,
              })),
              viewBounds,
            });
            void layout(newModel, setModel, flow, viewBounds, {
              duration: props.layoutDuration ?? LAYOUT_DURATION,
              forceFit: false,
            }).then(positions => {
              // Note we don't update positions until animation has finished
              chartCache.current.positions = positions;
              logger.debug('auto layout: completed', {
                positionCount: Object.keys(positions).length,
                positions,
              });
              return positions;
            });
          }
        } else {
          logger.debug('no layout needed: using cached/stored positions', {
            isManualLayout,
            cachedPositionCount: Object.keys(positions).length,
            workflowPositionCount: Object.keys(workflowPositions).length,
          });
          // if isManualLayout, then we use values from store instead
          newModel.nodes.forEach(n => {
            if (isManualLayout && n.type !== 'placeholder') {
              n.position = workflowPositions[n.id];
            } else if (!isManualLayout && positions[n.id]) {
              // In auto-layout mode, preserve cached positions from previous
              // layout
              n.position = positions[n.id];
            }
            ensureNodePosition(
              newModel,
              { ...positions, ...workflowPositions },
              n,
              positionOffsetMap
            );
          });
          setModel(newModel);
        }
      } else {
        logger.debug('flow not initialized: setting positions on newModel');
        // Flow not initialized yet, but we have nodes - ensure positions first
        newModel.nodes.forEach(n => {
          if (isManualLayout && n.type !== 'placeholder') {
            n.position = workflowPositions[n.id];
          } else if (!isManualLayout && positions[n.id]) {
            n.position = positions[n.id];
          }
          ensureNodePosition(
            newModel,
            { ...positions, ...workflowPositions },
            n,
            positionOffsetMap
          );
        });
        setModel(newModel);
      }
    } else if (workflow.jobs.length === 0 && placeholders.nodes.length === 0) {
      logger.debug('empty workflow: clearing canvas');
      // Explicitly empty workflow - show empty state
      // Only clear canvas when BOTH workflow.jobs and placeholders are empty
      // This prevents blank canvas during race conditions where placeholder
      // is cleared before Y.Doc observer fires
      setModel({ nodes: [], edges: [] });
      chartCache.current.positions = {};
    }
    // If newModel is empty but workflow has jobs, keep previous
    // model. This prevents blank canvas during state transitions.
  }, [
    workflow,
    flow,
    placeholders,
    el,
    isManualLayout,
    workflowPositions,
    selection,
    runSteps,
  ]);

  // This effect only runs when AI assistant visibility changes, not on every selection change
  useEffect(() => {
    if (!props.showAiAssistant) {
      setDrawerWidth(0);

      // Fit view when AI assistant panel closes
      if (flow && model.nodes.length > 0) {
        setTimeout(() => {
          const bounds = flow.getNodesBounds(model.nodes);
          void flow.fitBounds(bounds, {
            duration: FIT_DURATION,
            padding: FIT_PADDING,
          });
        }, 510);
      }

      return;
    }

    if (!props.aiAssistantId) {
      return;
    }

    const aiAssistantId = props.aiAssistantId;

    let observer: ResizeObserver | null = null;

    const timer = setTimeout(() => {
      const drawer = document.getElementById(aiAssistantId);
      if (drawer) {
        observer = new ResizeObserver(entries => {
          const entry = entries[0];
          if (entry) {
            const width = entry.contentRect.width;
            setDrawerWidth(width);
          }
        });
        observer.observe(drawer);
        setDrawerWidth(drawer.getBoundingClientRect().width);

        // Fit view when AI assistant panel opens
        if (flow && model.nodes.length > 0) {
          setTimeout(() => {
            const bounds = flow.getNodesBounds(model.nodes);
            void flow.fitBounds(bounds, {
              duration: FIT_DURATION,
              padding: FIT_PADDING,
            });
          }, 510);
        }
      }
    }, 50);

    return () => {
      clearTimeout(timer);
      if (observer) {
        observer.disconnect();
      }
    };
  }, [props.showAiAssistant, props.aiAssistantId]);

  const onNodesChange = useCallback(
    (changes: NodeChange[]) => {
      const newNodes = applyNodeChanges(changes, model.nodes);
      setModel({ nodes: newNodes, edges: model.edges });

      // we just need to recalculate this to update the cache.
      const newPositions = newNodes.reduce<Positions>((obj, next) => {
        obj[next.id] = next.position;
        return obj;
      }, {});
      chartCache.current.positions = newPositions;
    },
    [setModel, model]
  );

  const handleEdgeClick = useCallback(
    (_event: React.MouseEvent, edge: Flow.Edge) => {
      cancelPlaceholder();
      updateSelection(edge.id);
    },
    [updateSelection, cancelPlaceholder]
  );

  // Trigger a fit to bounds when the parent div changes size
  // Debounced to wait until resize completes before fitting
  useEffect(() => {
    if (flow && el) {
      let isFirstCallback = true;

      const debouncedResize = debounce(
        async (signal: AbortSignal) => {
          // Caller responsibility: only called when flow exists
          if (!flow) {
            logger.warn('fitBounds called without flow instance');
            return;
          }

          // Compute bounds based on current viewport
          const viewBounds = {
            width: el.clientWidth || 0,
            height: el.clientHeight || 0,
          };
          const rect = getVisibleRect(flow.getViewport(), viewBounds, 1);
          const visible = model.nodes.filter(n =>
            isPointInRect(n.position, rect)
          );
          const targetBounds = flow.getNodesBounds(visible);

          // Validate rect has finite numbers (borrowed from safeFitBoundsRect logic)
          const isValidRect =
            targetBounds &&
            Number.isFinite(targetBounds.x) &&
            Number.isFinite(targetBounds.y) &&
            Number.isFinite(targetBounds.width) &&
            Number.isFinite(targetBounds.height);

          if (!isValidRect) {
            logger.warn('fitBounds called with invalid rect', targetBounds);
            return;
          }

          // Check if aborted before async operation
          if (signal.aborted) {
            return;
          }

          try {
            // Wait for fitBounds animation to complete
            await flow.fitBounds(targetBounds, {
              duration: FIT_DURATION,
              padding: FIT_PADDING,
            });
          } catch (err) {
            logger.error('fitBounds failed', err);
          }
        },
        200 // ~200ms after resize stops
      );

      const resizeOb = new ResizeObserver(_entries => {
        if (!isFirstCallback) {
          // Don't fit when the listener attaches (it callsback immediately)
          debouncedResize();
        }
        isFirstCallback = false;
      });
      resizeOb.observe(el);

      return () => {
        debouncedResize.cancel();
        resizeOb.unobserve(el);
      };
    }
  }, [flow, model, el]);

  const switchLayout = () => {
    if (isManualLayout) {
      updatePositions(null);
    } else {
      updatePositions(chartCache.current.positions);
    }
  };

  const handleFitView = useCallback(() => {
    if (!flow) return;
    const bounds = flow.getNodesBounds(model.nodes);
    void flow.fitBounds(bounds, {
      duration: 200,
      padding: FIT_PADDING,
    });
  }, [model, flow]);

  // Modal handlers for adaptor selection
  const showAdaptorModal = useCallback(
    (sourceNode: Flow.Node, position: { x: number; y: number }) => {
      setPendingPlaceholder({
        sourceNode,
        position,
      });
    },
    []
  );

  const handleAdaptorSelect = useCallback(
    (adaptorSpec: string) => {
      if (!pendingPlaceholder) return;

      const { sourceNode, position } = pendingPlaceholder;

      // Extract adaptor display name (e.g., "salesforce" from "@openfn/language-salesforce@2.0.0")
      const adaptorDisplayName = getAdaptorDisplayName(adaptorSpec, {
        titleCase: true,
        fallback: 'Unknown',
      });

      // Generate job ID
      const jobId = randomUUID();

      // Create job directly in Y.Doc (this will trigger animation)
      const newJob = {
        id: jobId,
        name: adaptorDisplayName,
        body: '',
        adaptor: adaptorSpec,
      };

      workflowStore.addJob(newJob);

      if (isManualLayout) {
        workflowStore.updatePosition(jobId, position);
      }

      // Create edge connecting source to new job
      // TODO: This edge creation logic is duplicated in useConnect.ts
      // (onConnect callback) and above in handleCommit. Consider extracting
      // to a shared helper like createEdgeForSource() to avoid inconsistencies.
      const sourceIsJob = isSourceNodeJob(sourceNode.id, jobs);
      const newEdge: Workflow.Edge = {
        id: randomUUID(),
        target_job_id: jobId,
        condition_type: 'on_job_success',
        enabled: true,
      };

      if (sourceIsJob) {
        newEdge.source_job_id = sourceNode.id;
        newEdge.source_trigger_id = null;
      } else {
        newEdge.source_job_id = null;
        newEdge.source_trigger_id = sourceNode.id;
      }

      workflowStore.addEdge(newEdge);

      // Clear pending state
      setPendingPlaceholder(null);

      // Select the new job to open inspector
      updateSelection(jobId);
    },
    [pendingPlaceholder, workflowStore, isManualLayout, jobs, updateSelection]
  );

  const handleAdaptorModalClose = useCallback(() => {
    setPendingPlaceholder(null);
  }, []);

  // Show modal immediately without creating placeholder yet
  const showModalThenAnimate = useCallback(
    (sourceNode: Flow.Node, position?: { x: number; y: number }) => {
      const defaultPosition = position || {
        x: sourceNode.position.x,
        y: sourceNode.position.y + 120,
      };

      showAdaptorModal(sourceNode, defaultPosition);
    },
    [showAdaptorModal]
  );

  const handleNodeClick = useCallback(
    (event: React.MouseEvent, node: Flow.Node) => {
      const target = event.target as HTMLElement;
      const handleId = target.getAttribute('data-handleid');

      if (handleId === 'node-connector') {
        // Clicking the + button shows modal immediately
        // Node will animate in after adaptor is selected
        showModalThenAnimate(node);
        return;
      }

      if (node.type !== 'placeholder') cancelPlaceholder();
      updateSelection(node.id);
    },
    [updateSelection, cancelPlaceholder, showModalThenAnimate]
  );

  // update node position data only on dragstop.
  const onNodeDragStop = useCallback(
    (
      _e: React.MouseEvent,
      node: Flow.Node,
      _nodes: Flow.Node[],
      isClick: boolean
    ) => {
      // a click was registered as a drag
      if (isClick) {
        handleNodeClick(_e, node);
        return;
      }
      if (node.type === 'placeholder') {
        updatePlaceholderPosition(node.id, node.position);
      } else {
        updatePosition(node.id, node.position);
      }
    },
    [updatePosition, updatePlaceholderPosition, handleNodeClick]
  );

  const connectHandlers = useConnect(
    model,
    setModel,
    showModalThenAnimate,
    () => {
      cancelPlaceholder();
      updateSelection(null);
    },
    flow,
    workflowStore
  );
  // Set up tooltips for control buttons
  useTippyForControls(isManualLayout, canUndo, canRedo);

  // undo/redo keyboard shortcuts
  useEffect(() => {
    const keyHandler = (e: KeyboardEvent) => {
      const isUndo = (e.metaKey || e.ctrlKey) && !e.shiftKey && e.key === 'z';
      const isRedo =
        ((e.metaKey || e.ctrlKey) && e.key === 'y') ||
        ((e.metaKey || e.ctrlKey) && e.shiftKey && e.key === 'z');

      if (isUndo) {
        e.preventDefault();
        undo();
      }
      if (isRedo) {
        e.preventDefault();
        redo();
      }
    };
    window.addEventListener('keydown', keyHandler);
    return () => {
      window.removeEventListener('keydown', keyHandler);
    };
  }, [redo, undo]);

  return (
    <>
      <ReactFlow
        ref={workflowDiagramRef}
        maxZoom={1}
        proOptions={{ account: 'paid-pro', hideAttribution: true }}
        nodes={model.nodes}
        edges={model.edges}
        onNodesChange={onNodesChange}
        onNodeDragStart={flowhandlers.ondragstart()}
        onNodeDragStop={flowhandlers.ondragstop(onNodeDragStop)}
        nodesDraggable={isManualLayout}
        nodeTypes={nodeTypes}
        edgeTypes={edgeTypes}
        onNodeClick={handleNodeClick}
        onEdgeClick={handleEdgeClick}
        deleteKeyCode={null}
        fitView
        fitViewOptions={{ padding: FIT_PADDING }}
        minZoom={0.2}
        {...connectHandlers}
      >
        {(jobs.length > 0 || triggers.length > 0) && (
          <Controls
            position="bottom-left"
            showInteractive={false}
            showFitView={false}
            style={{
              transform: `translateX(${drawerWidth.toString()}px)`,
              transition: 'transform 500ms ease-in-out',
            }}
          >
            <ControlButton onClick={handleFitView} data-tooltip="Fit view">
              <span className="text-black hero-viewfinder-circle w-4 h-4" />
            </ControlButton>

            <ControlButton
              onClick={() => switchLayout()}
              data-tooltip={
                isManualLayout
                  ? 'Switch to auto layout mode'
                  : 'Switch to manual layout mode'
              }
            >
              {isManualLayout ? (
                <span className="text-black hero-cursor-arrow-rays w-4 h-4" />
              ) : (
                <span className="text-black hero-cursor-arrow-ripple w-4 h-4" />
              )}
            </ControlButton>
            <ControlButton
              onClick={() => void forceLayout()}
              data-tooltip="Run auto layout (override manual positions)"
            >
              <span className="text-black hero-squares-2x2 w-4 h-4" />
            </ControlButton>
            <ControlButton
              onClick={() => undo()}
              data-tooltip={canUndo ? 'Undo' : 'Nothing to undo'}
              data-testid="undo-button"
              disabled={!canUndo}
            >
              <span className="text-black hero-arrow-uturn-left w-4 h-4" />
            </ControlButton>
            <ControlButton
              onClick={() => redo()}
              data-tooltip={canRedo ? 'Redo' : 'Nothing to redo'}
              data-testid="redo-button"
              disabled={!canRedo}
            >
              <span className="text-black hero-arrow-uturn-right w-4 h-4" />
            </ControlButton>
          </Controls>
        )}
        <Background />
        {(jobs.length > 0 || triggers.length > 0) && (
          <MiniMap
            zoomable
            pannable
            className="border-2 border-gray-200"
            nodeComponent={props => (
              <MiniMapNode {...props} jobs={jobs} triggers={triggers} />
            )}
          />
        )}
        <PointerTrackerViewer containerEl={props.containerEl} />
      </ReactFlow>

      <AdaptorSelectionModal
        isOpen={pendingPlaceholder !== null}
        onClose={handleAdaptorModalClose}
        onSelect={handleAdaptorSelect}
        projectAdaptors={projectAdaptors}
      />
    </>
  );
}
