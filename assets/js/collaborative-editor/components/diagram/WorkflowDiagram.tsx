import {
  applyNodeChanges,
  Background,
  ControlButton,
  Controls,
  MiniMap,
  type NodeChange,
  ReactFlow,
  ReactFlowProvider,
  type Rect,
  useReactFlow,
} from "@xyflow/react";
import React, { useCallback, useEffect, useRef, useState } from "react";
import tippy from "tippy.js";

import {
  useWorkflowState,
  usePositions,
  useWorkflowStoreContext,
} from "#/collaborative-editor/hooks/useWorkflow";
import _logger from "#/utils/logger";
import MiniMapNode from "#/workflow-diagram/components/MiniMapNode";
import { FIT_DURATION, FIT_PADDING } from "#/workflow-diagram/constants";
import edgeTypes from "#/workflow-diagram/edges";
import layout from "#/workflow-diagram/layout";
import nodeTypes from "#/workflow-diagram/nodes";
import type { Flow, Positions } from "#/workflow-diagram/types";
import useConnect from "#/workflow-diagram/useConnect";
import usePlaceholders from "#/workflow-diagram/usePlaceholders";
import { ensureNodePosition } from "#/workflow-diagram/util/ensure-node-position";
import fromWorkflow from "#/workflow-diagram/util/from-workflow";
import shouldLayout from "#/workflow-diagram/util/should-layout";
import throttle from "#/workflow-diagram/util/throttle";
import updateSelectionStyles from "#/workflow-diagram/util/update-selection";
import {
  getVisibleRect,
  isPointInRect,
} from "#/workflow-diagram/util/viewport";

import { useInspectorOverlap } from "./useInspectorOverlap";

type WorkflowDiagramProps = {
  el?: HTMLElement | null;
  containerEl?: HTMLElement | null;
  selection: string | null;
  onSelectionChange: (id: string | null) => void;
  forceFit?: boolean;
  showAiAssistant?: boolean;
  aiAssistantId?: string;
  showInspector?: boolean;
  inspectorId?: string | undefined;
  layoutDuration?: number;
};

type ChartCache = {
  positions: Positions;
  lastSelection: string | null;
  lastLayout?: string | undefined;
  layoutDuration?: number;
};

const LAYOUT_DURATION = 300;

// Simple React hook for Tippy tooltips that finds buttons by their content
const useTippyForControls = (isManualLayout: boolean) => {
  useEffect(() => {
    // Find the control buttons and initialize tooltips based on their dataset attributes
    const buttons = document.querySelectorAll(".react-flow__controls button");

    const cleaner: (() => void)[] = [];
    buttons.forEach(button => {
      if (button instanceof HTMLElement && button.dataset["tooltip"]) {
        const tp = tippy(button, {
          content: button.dataset["tooltip"],
          placement: "right",
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
  }, [isManualLayout]); // Only run once on mount
};

const logger = _logger.ns("WorkflowDiagram").seal();

export default function WorkflowDiagram(props: WorkflowDiagramProps) {
  const flowInstance = useReactFlow();
  const [flow, setFlow] = useState<typeof flowInstance | null>(null);
  // value of select in props seems same as select in store.
  // one in props is always set on initial render. (helps with refresh)
  const { selection, onSelectionChange, containerEl: el, inspectorId } = props;

  // Get Y.Doc workflow store for placeholder operations
  const workflowStore = useWorkflowStoreContext();

  // Get workflow actions including position updates
  const {
    positions: workflowPositions,
    updatePosition,
    updatePositions,
  } = usePositions();

  // TODO: implement these
  const undo = useCallback(() => {}, []);
  const redo = useCallback(() => {}, []);

  const { jobs, triggers, edges } = useWorkflowState(state => ({
    jobs: state.jobs,
    triggers: state.triggers,
    edges: state.edges,
  }));

  // TODO: implement disabled state - not currently available in WorkflowState
  const disabled = false;

  const workflow = React.useMemo(
    () => ({
      jobs,
      triggers,
      edges,
      disabled,
    }),
    [jobs, triggers, edges, disabled]
  );

  const isManualLayout = Object.keys(workflowPositions).length > 0;

  const [model, setModel] = useState<Flow.Model>({ nodes: [], edges: [] });
  const [drawerWidth, setDrawerWidth] = useState(0);
  const workflowDiagramRef = useRef<HTMLDivElement>(null);

  // Use custom hook for inspector overlap calculation
  const miniMapRightOffset = useInspectorOverlap(
    inspectorId,
    workflowDiagramRef
  );

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
    add: addPlaceholder,
    cancel: cancelPlaceholder,
    updatePlaceholderPosition,
  } = usePlaceholders(el, isManualLayout, updateSelection);

  // Override the placeholder commit handler to use Y.Doc store
  useEffect(() => {
    if (!el) return;

    const handleCommit = (evt: CustomEvent) => {
      const { id, name } = evt.detail;

      // Get placeholder data
      const placeholderNode = placeholders.nodes[0];
      const placeholderEdge = placeholders.edges[0];

      if (!placeholderNode) {
        // Add defensive logging in dev mode
        if (process.env["NODE_ENV"] !== "production") {
          console.warn(
            "[WorkflowDiagram] handleCommit: placeholder node not found",
            {
              eventId: id,
              eventName: name,
              placeholdersState: placeholders,
              workflowJobs: workflow.jobs.length,
            }
          );
        }
        return;
      }

      // Cast data to access placeholder-specific properties
      const nodeData = placeholderNode.data as any;

      // Create job data for Y.Doc
      const newJob = {
        id,
        name,
        body: nodeData.body as string,
        adaptor: nodeData.adaptor as string,
      };

      // Add to Y.Doc store (synchronous transaction)
      workflowStore.addJob(newJob);

      // Handle position for manual layout mode
      if (isManualLayout) {
        workflowStore.updatePosition(id, placeholderNode.position);
      }

      // Create edge if placeholder has one
      if (placeholderEdge) {
        const edgeData = placeholderEdge.data as any;

        // Determine if source is a job or trigger by checking workflow state
        const sourceIsJob = jobs.some(j => j.id === placeholderEdge.source);

        const newEdge: Record<string, any> = {
          id: placeholderEdge.id,
          target_job_id: id,
          condition_type: edgeData?.condition_type || "on_job_success",
          enabled: true,
        };

        // Set either source_job_id or source_trigger_id
        if (sourceIsJob) {
          newEdge["source_job_id"] = placeholderEdge.source;
          newEdge["source_trigger_id"] = null;
        } else {
          newEdge["source_job_id"] = null;
          newEdge["source_trigger_id"] = placeholderEdge.source;
        }

        workflowStore.addEdge(newEdge);
      }

      // FIX: Clear placeholder AFTER Y.Doc updates
      // Y.Doc transactions are synchronous, so the store state is already
      // updated. Canvas will re-render with new job before placeholder is
      // cleared, preventing blank canvas during race conditions.
      cancelPlaceholder();

      // Select the new job
      updateSelection(id);
    };

    // Attach our custom commit handler
    el.addEventListener("commit-placeholder" as any, handleCommit);

    return () => {
      el.removeEventListener("commit-placeholder" as any, handleCommit);
    };
  }, [
    el,
    placeholders,
    isManualLayout,
    workflowStore,
    updateSelection,
    jobs,
    cancelPlaceholder,
    workflow.jobs.length,
  ]);

  // Track positions and selection on a ref, as a passive cache, to prevent re-renders
  const chartCache = useRef<ChartCache>({
    positions: {},
    // This will set the initial selection into the cache
    lastSelection: selection,
    lastLayout: undefined,
  });

  const forceLayout = useCallback(() => {
    if (!flow) return Promise.resolve({});

    const viewBounds = {
      width: workflowDiagramRef.current?.clientWidth ?? 0,
      height: workflowDiagramRef.current?.clientHeight ?? 0,
    };
    return layout(model, setModel, flow, viewBounds, {
      duration: props.layoutDuration ?? LAYOUT_DURATION,
      forceFit: props.forceFit ?? false,
    }).then(positions => {
      // Note we don't update positions until the animation has finished
      chartCache.current.positions = positions;
      if (isManualLayout) updatePositions(positions);
      return positions;
    });
  }, [
    flow,
    model,
    isManualLayout,
    updatePositions,
    props.layoutDuration,
    props.forceFit,
  ]);

  // Respond to changes pushed into the component from outside
  // This usually means the workflow has changed or its the first load, so we don't want to animate
  // Later, if responding to changes from other users live, we may want to animate
  useEffect(() => {
    // Clear cache if positions were cleared (e.g., after reset workflow)
    // This prevents stale cached positions from being used when Y.Doc positions are empty
    // Also clear lastLayout so shouldLayout() will trigger a new layout
    if (
      Object.keys(workflowPositions).length === 0 &&
      Object.keys(chartCache.current.positions).length > 0
    ) {
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
    logger.log("calling fromWorkflow");

    const newModel = updateSelectionStyles(
      fromWorkflow(
        workflow,
        positions,
        placeholders,
        { steps: [] },
        // Use current selection prop, not cached lastSelection
        // This ensures URL changes (from Header Run button) highlight nodes
        selection
      ),
      selection
    );
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

        if (layoutId) {
          chartCache.current.lastLayout = layoutId;
          const viewBounds = {
            width: workflowDiagramRef.current?.clientWidth ?? 0,
            height: workflowDiagramRef.current?.clientHeight ?? 0,
          };
          if (isManualLayout) {
            // give nodes positions
            const nodesWPos = newModel.nodes.map(node => {
              // during manualLayout. a placeholder wouldn't have position in
              // positions in store hence use the position on the placeholder
              // node
              const isPlaceholder = node.type === "placeholder";

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
          } else {
            void layout(newModel, setModel, flow, viewBounds, {
              duration: props.layoutDuration ?? LAYOUT_DURATION,
              forceFit: props.forceFit ?? false,
            }).then(positions => {
              // Note we don't update positions until animation has finished
              chartCache.current.positions = positions;
              return positions;
            });
          }
        } else {
          // if isManualLayout, then we use values from store instead
          newModel.nodes.forEach(n => {
            if (isManualLayout && n.type !== "placeholder") {
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
        // Flow not initialized yet, but we have nodes - ensure positions first
        newModel.nodes.forEach(n => {
          if (isManualLayout && n.type !== "placeholder") {
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
      // DEFENSIVE: Explicitly empty workflow - show empty state
      // Only clear canvas when BOTH workflow.jobs and placeholders are empty
      // This prevents blank canvas during race conditions where placeholder
      // is cleared before Y.Doc observer fires
      setModel({ nodes: [], edges: [] });
      chartCache.current.positions = {};
    }
    // DEFENSIVE: If newModel is empty but workflow has jobs, keep previous
    // model. This prevents blank canvas during state transitions.
  }, [
    workflow,
    flow,
    placeholders,
    el,
    isManualLayout,
    workflowPositions,
    selection,
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

  useEffect(() => {
    if (props.forceFit && flow && model.nodes.length > 0) {
      // Immediately fit to bounds when forceFit becomes true
      const bounds = flow.getNodesBounds(model.nodes);
      flow
        .fitBounds(bounds, {
          duration: FIT_DURATION,
          padding: FIT_PADDING,
        })
        .catch(error => {
          logger.error("Failed to fit bounds:", error);
        });
    }
  }, [props.forceFit, flow, model.nodes]);

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

  // update node position data only on dragstop.
  const onNodeDragStop = useCallback(
    (_e: React.MouseEvent, node: Flow.Node) => {
      if (node.type === "placeholder") {
        updatePlaceholderPosition(node.id, node.position);
      } else {
        updatePosition(node.id, node.position);
      }
    },
    [updatePosition, updatePlaceholderPosition]
  );

  const handleNodeClick = useCallback(
    (event: React.MouseEvent, node: Flow.Node) => {
      if (
        (event.target as HTMLElement).getAttribute("data-handleid") ===
        "node-connector"
      ) {
        addPlaceholder(node);
        return;
      }
      if (node.type !== "placeholder") cancelPlaceholder();
      updateSelection(node.id);
    },
    [updateSelection, cancelPlaceholder, addPlaceholder]
  );

  const handleEdgeClick = useCallback(
    (_event: React.MouseEvent, edge: Flow.Edge) => {
      cancelPlaceholder();
      updateSelection(edge.id);
    },
    [updateSelection, cancelPlaceholder]
  );

  // Trigger a fit to bounds when the parent div changes size
  // To keep the chart more stable, try and take a snapshot of the target bounds
  // when a new resize starts
  // This will be imperfect but stops the user completely losing context
  useEffect(() => {
    if (flow && el) {
      let isFirstCallback = true;

      let cachedTargetBounds: Rect | null = null;
      let cacheTimeout: NodeJS.Timeout | undefined;

      const throttledResize = throttle(() => {
        if (cacheTimeout) clearTimeout(cacheTimeout);

        // After 3 seconds, clear the timeout and take a new cache snapshot
        cacheTimeout = setTimeout(() => {
          cachedTargetBounds = null;
        }, 3000);

        if (!cachedTargetBounds) {
          // Take a snapshot of what bounds to try and maintain throughout the resize
          const viewBounds = {
            width: el.clientWidth || 0,
            height: el.clientHeight || 0,
          };
          const rect = getVisibleRect(flow.getViewport(), viewBounds, 1);
          const visible = model.nodes.filter(n =>
            isPointInRect(n.position, rect)
          );
          cachedTargetBounds = flow.getNodesBounds(visible);
        }

        // Run an animated fit
        flow.fitBounds(cachedTargetBounds, {
          duration: FIT_DURATION,
          padding: FIT_PADDING,
        });
      }, FIT_DURATION * 2);

      const resizeOb = new ResizeObserver(_entries => {
        if (!isFirstCallback) {
          // Don't fit when the listener attaches (it callsback immediately)
          throttledResize();
        }
        isFirstCallback = false;
      });
      resizeOb.observe(el);

      return () => {
        throttledResize.cancel();
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

  const connectHandlers = useConnect(
    model,
    setModel,
    addPlaceholder,
    () => {
      cancelPlaceholder();
      updateSelection(null);
    },
    flowInstance
  );
  // Set up tooltips for control buttons
  useTippyForControls(isManualLayout);

  // undo/redo keyboard shortcuts
  useEffect(() => {
    const keyHandler = (e: KeyboardEvent) => {
      const isUndo = (e.metaKey || e.ctrlKey) && !e.shiftKey && e.key === "z";
      const isRedo =
        ((e.metaKey || e.ctrlKey) && e.key === "y") ||
        ((e.metaKey || e.ctrlKey) && e.shiftKey && e.key === "z");

      if (isUndo) {
        e.preventDefault();
        undo();
      }
      if (isRedo) {
        e.preventDefault();
        redo();
      }
    };
    window.addEventListener("keydown", keyHandler);
    return () => {
      window.removeEventListener("keydown", keyHandler);
    };
  }, [redo, undo]);

  return (
    <ReactFlowProvider>
      <ReactFlow
        ref={workflowDiagramRef}
        maxZoom={1}
        proOptions={{ account: "paid-pro", hideAttribution: true }}
        nodes={model.nodes}
        edges={model.edges}
        onNodesChange={onNodesChange}
        onNodeDragStop={onNodeDragStop}
        nodesDraggable={isManualLayout}
        nodeTypes={nodeTypes}
        edgeTypes={edgeTypes}
        onNodeClick={handleNodeClick}
        onEdgeClick={handleEdgeClick}
        onInit={setFlow}
        deleteKeyCode={null}
        fitView
        fitViewOptions={{ padding: FIT_PADDING }}
        minZoom={0.2}
        {...connectHandlers}
      >
        <Controls
          position="bottom-left"
          showInteractive={false}
          showFitView={false}
          style={{
            transform: `translateX(${drawerWidth.toString()}px)`,
            transition: "transform 500ms ease-in-out",
          }}
        >
          <ControlButton onClick={handleFitView} data-tooltip="Fit view">
            <span className="text-black hero-viewfinder-circle w-4 h-4" />
          </ControlButton>

          <ControlButton
            onClick={() => switchLayout()}
            data-tooltip={
              isManualLayout
                ? "Switch to auto layout mode"
                : "Switch to manual layout mode"
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
          <ControlButton onClick={() => undo()} data-tooltip="Undo">
            <span className="text-black hero-arrow-uturn-left w-4 h-4" />
          </ControlButton>
          <ControlButton onClick={() => redo()} data-tooltip="Redo">
            <span className="text-black hero-arrow-uturn-right w-4 h-4" />
          </ControlButton>
        </Controls>
        <Background />
        <MiniMap
          zoomable
          pannable
          className="border-2 border-gray-200"
          nodeComponent={MiniMapNode}
          style={{
            transform: `translateX(-${miniMapRightOffset.toString()}px)`,
            transition: "transform duration-300 ease-in-out",
          }}
        />
      </ReactFlow>
    </ReactFlowProvider>
  );
}
