/**
 * WorkflowEditor - Main workflow editing component
 */

import { useCallback, useEffect, useRef } from 'react';

import { useURLState } from '#/react/lib/use-url-state';

import { useIsNewWorkflow, useProject } from '../hooks/useSessionContext';
import {
  useIsRunPanelOpen,
  useRunPanelContext,
  useUICommands,
  useIsAIAssistantPanelOpen,
  useShowLandingScreen,
} from '../hooks/useUI';
import {
  useNodeSelection,
  useWorkflowActions,
  useWorkflowState,
  useWorkflowStoreContext,
} from '../hooks/useWorkflow';
import { useKeyboardShortcut } from '../keyboard';
import { Z_INDEX } from '../utils/constants';

import { CollaborativeWorkflowDiagram } from './diagram/CollaborativeWorkflowDiagram';
import { FullScreenIDE } from './ide/FullScreenIDE';
import { Inspector } from './inspector';
import { ManualRunPanel } from './ManualRunPanel';
import { ManualRunPanelErrorBoundary } from './ManualRunPanelErrorBoundary';

interface WorkflowEditorProps {
  parentProjectId?: string | null;
  parentProjectName?: string | null;
}

export function WorkflowEditor({
  parentProjectId = null,
  parentProjectName = null,
}: WorkflowEditorProps = {}) {
  const { params, updateSearchParams } = useURLState();
  const { currentNode, selectNode } = useNodeSelection();
  const workflowStore = useWorkflowStoreContext();
  const isNewWorkflow = useIsNewWorkflow();
  const showLandingScreen = useShowLandingScreen();
  const { saveWorkflow } = useWorkflowActions();

  const isRunPanelOpen = useIsRunPanelOpen();
  const runPanelContext = useRunPanelContext();
  const { closeRunPanel, openRunPanel, openYAMLImportModal } = useUICommands();
  const isAIAssistantPanelOpen = useIsAIAssistantPanelOpen();

  const isSyncingRef = useRef(false);
  const isInitialMountRef = useRef(true);

  useEffect(() => {
    if (isSyncingRef.current) return;

    const panelParam = params['panel'] ?? null;

    if (isRunPanelOpen) {
      const contextJobId = runPanelContext?.jobId;
      const contextTriggerId = runPanelContext?.triggerId;
      // runMode persists the panel entry point in the URL so the title
      // ("Pick a custom input") survives reload, deep-link, and back/forward.
      // Read back by the URL→store sync below.
      const contextEntryPoint = runPanelContext?.entryPoint ?? null;
      const runModeParam =
        contextEntryPoint === 'custom-input' ? 'custom-input' : null;

      // run panel can override all panels
      const nodePanels = ['editor', 'run', 'code', 'settings'].includes(
        panelParam
      );
      if (!nodePanels) {
        isSyncingRef.current = true;
        if (contextJobId) {
          updateSearchParams({
            panel: 'run',
            job: contextJobId,
            trigger: null,
            runMode: runModeParam,
          });
        } else if (contextTriggerId) {
          updateSearchParams({
            panel: 'run',
            trigger: contextTriggerId,
            job: null,
            runMode: runModeParam,
          });
        } else {
          updateSearchParams({ panel: 'run', runMode: runModeParam });
        }
        setTimeout(() => {
          isSyncingRef.current = false;
        }, 0);
      }
    } else if (
      !isRunPanelOpen &&
      panelParam === 'run' &&
      !isSyncingRef.current &&
      !isInitialMountRef.current
    ) {
      isSyncingRef.current = true;
      updateSearchParams({ panel: null, runMode: null });
      setTimeout(() => {
        isSyncingRef.current = false;
      }, 0);
    }
  }, [isRunPanelOpen, runPanelContext, params, updateSearchParams]);

  useEffect(() => {
    // On /new, URL params can't drive panel state — the landing screen is the
    // only valid entry point and the canvas/panels shouldn't be reachable.
    if (isNewWorkflow) return;

    const panelParam = params['panel'] ?? null;

    if (panelParam === 'run' && !isRunPanelOpen) {
      isSyncingRef.current = true;

      const jobParam = params['job'] ?? null;
      const triggerParam = params['trigger'] ?? null;
      const entryPointFromUrl =
        params['runMode'] === 'custom-input'
          ? { entryPoint: 'custom-input' as const }
          : {};

      if (jobParam) {
        openRunPanel({ jobId: jobParam, ...entryPointFromUrl });
      } else if (triggerParam) {
        openRunPanel({ triggerId: triggerParam, ...entryPointFromUrl });
      } else if (currentNode.type === 'job' && currentNode.node) {
        openRunPanel({
          jobId: currentNode.node.id,
          ...entryPointFromUrl,
        });
      } else if (currentNode.type === 'trigger' && currentNode.node) {
        openRunPanel({
          triggerId: currentNode.node.id,
          ...entryPointFromUrl,
        });
      } else {
        const firstTrigger = workflow.triggers[0];
        if (firstTrigger?.id) {
          openRunPanel({
            triggerId: firstTrigger.id,
            entryPoint: 'custom-input',
          });
        }
      }

      setTimeout(() => {
        isSyncingRef.current = false;
        isInitialMountRef.current = false;
      }, 0);
    } else if (panelParam !== 'run' && isRunPanelOpen) {
      isSyncingRef.current = true;
      closeRunPanel();

      setTimeout(() => {
        isSyncingRef.current = false;
        isInitialMountRef.current = false;
      }, 0);
    } else {
      setTimeout(() => {
        isInitialMountRef.current = false;
      }, 0);
    }
  }, [
    isNewWorkflow,
    params,
    isRunPanelOpen,
    currentNode.type,
    currentNode.node,
    openRunPanel,
    closeRunPanel,
  ]);

  useEffect(() => {
    if (isRunPanelOpen && currentNode.node) {
      if (currentNode.type === 'job') {
        if (runPanelContext?.jobId !== currentNode.node.id) {
          openRunPanel({ jobId: currentNode.node.id });
        }
      } else if (currentNode.type === 'trigger') {
        if (runPanelContext?.triggerId !== currentNode.node.id) {
          openRunPanel({ triggerId: currentNode.node.id });
        }
      } else if (currentNode.type === 'edge') {
        if (runPanelContext?.edgeId !== currentNode.node.id) {
          openRunPanel({ edgeId: currentNode.node.id });
        }
      }
    }
  }, [
    currentNode.type,
    currentNode.node,
    isRunPanelOpen,
    runPanelContext,
    openRunPanel,
    closeRunPanel,
  ]);

  const project = useProject();
  const projectId = project?.id;

  const workflowState = useWorkflowState(state => state.workflow!);
  const workflowId = workflowState.id;

  const workflow = useWorkflowState(state => ({
    ...state.workflow!,
    jobs: state.jobs,
    triggers: state.triggers,
    edges: state.edges,
    positions: state.positions,
  }));

  // Helper function to clear workflow from canvas
  const clearCanvas = useCallback(() => {
    if (
      workflow.jobs.length > 0 ||
      workflow.triggers.length > 0 ||
      workflow.edges.length > 0
    ) {
      // Remove all edges first
      workflow.edges.forEach(edge => {
        workflowStore.removeEdge(edge.id);
      });

      // Remove all jobs
      workflow.jobs.forEach(job => {
        workflowStore.removeJob(job.id);
      });

      // Remove all triggers using the store method
      workflowStore.clearAllTriggers();
    }
  }, [workflow.jobs, workflow.triggers, workflow.edges, workflowStore]);

  // Clear canvas when the AI Assistant panel opens for a new workflow, to
  // prepare for an AI-generated workflow.
  const prevAIPanelOpenRef = useRef(isAIAssistantPanelOpen);
  const hasInitializedRef = useRef(false);

  useEffect(() => {
    // Skip clearing on initial mount - let URL state restoration handle it
    if (!hasInitializedRef.current) {
      hasInitializedRef.current = true;
      prevAIPanelOpenRef.current = isAIAssistantPanelOpen;
      return;
    }

    if (!isNewWorkflow) {
      // Update ref but don't clear for existing workflows
      prevAIPanelOpenRef.current = isAIAssistantPanelOpen;
      return;
    }

    const aiPanelJustOpened =
      !prevAIPanelOpenRef.current && isAIAssistantPanelOpen;

    if (aiPanelJustOpened) {
      clearCanvas();
    }

    prevAIPanelOpenRef.current = isAIAssistantPanelOpen;
  }, [isAIAssistantPanelOpen, isNewWorkflow, clearCanvas]);

  const isIDEOpen = !isNewWorkflow && params['panel'] === 'editor';
  const selectedJobId = params['job'] ?? null;

  const handleCloseIDE = useCallback(() => {
    updateSearchParams({ panel: null });
  }, [updateSearchParams]);

  const handleCloseInspector = () => {
    selectNode(null);
  };

  // On /new, no nodes exist yet and the landing screen is the only valid UI.
  // Block Inspector and IDE so URL params like ?panel=settings can't open them.
  const showInspector =
    !isNewWorkflow &&
    (params['panel'] === 'settings' ||
      params['panel'] === 'code' ||
      params['panel'] === 'publish-template' ||
      Boolean(currentNode.node));

  /**
   * Keyboard shortcut for the YAML import modal.
   *
   * Only works when creating a new workflow (isNewWorkflow=true):
   * - Cmd/Ctrl + \ : Open the YAML import modal (from the landing screen)
   * - Cmd/Ctrl + K : Toggle AI Assistant (handled in AIAssistantPanelWrapper)
   *
   * Note: Using comma-separated combos for cross-platform support.
   * The tinykeys library parses these and binds to the appropriate key.
   */
  useKeyboardShortcut(
    'Control+\\, Meta+\\',
    () => {
      if (!isNewWorkflow) return;
      if (showLandingScreen) {
        openYAMLImportModal();
      }
      // left-panel path removed — see #4876
    },
    0,
    { enabled: isNewWorkflow }
  );

  useKeyboardShortcut(
    'Control+e, Meta+e',
    () => {
      if (currentNode.type !== 'job' || !currentNode.node) return;
      updateSearchParams({ panel: 'editor' });
    },
    0,
    { enabled: !isIDEOpen }
  );

  return (
    <div className="flex h-full w-full">
      <div className="flex-1 relative">
        <CollaborativeWorkflowDiagram inspectorId="inspector" />

        {!isRunPanelOpen && (
          <div
            id="inspector"
            style={{ zIndex: Z_INDEX.INSPECTOR }}
            className={`absolute top-0 right-0 transition-transform duration-300 ease-in-out ${
              showInspector
                ? 'translate-x-0'
                : 'translate-x-full pointer-events-none'
            }`}
          >
            <Inspector
              currentNode={currentNode}
              onClose={handleCloseInspector}
              onOpenRunPanel={openRunPanel}
            />
          </div>
        )}

        {isRunPanelOpen && runPanelContext && projectId && workflowId && (
          <div
            style={{ zIndex: Z_INDEX.RUN_PANEL }}
            className="absolute inset-y-0 right-0 flex pointer-events-none"
          >
            <ManualRunPanelErrorBoundary onClose={closeRunPanel}>
              <ManualRunPanel
                workflow={workflow}
                projectId={projectId}
                workflowId={workflowId}
                jobId={runPanelContext.jobId ?? null}
                triggerId={runPanelContext.triggerId ?? null}
                edgeId={runPanelContext.edgeId ?? null}
                entryPoint={runPanelContext.entryPoint ?? null}
                onClose={closeRunPanel}
                saveWorkflow={saveWorkflow}
              />
            </ManualRunPanelErrorBoundary>
          </div>
        )}
      </div>

      {isIDEOpen && selectedJobId && (
        <FullScreenIDE
          jobId={selectedJobId}
          onClose={handleCloseIDE}
          parentProjectId={parentProjectId}
          parentProjectName={parentProjectName}
        />
      )}
    </div>
  );
}
