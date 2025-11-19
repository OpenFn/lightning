/**
 * WorkflowEditor - Main workflow editing component
 */

import { useEffect, useRef, useState } from 'react';

import { useURLState } from '../../react/lib/use-url-state';
import type { WorkflowState as YAMLWorkflowState } from '../../yaml/types';
import { useIsNewWorkflow, useProject } from '../hooks/useSessionContext';
import { useKeyboardShortcut } from '../keyboard';
import {
  useIsRunPanelOpen,
  useRunPanelContext,
  useUICommands,
} from '../hooks/useUI';
import {
  useCanRun,
  useNodeSelection,
  useWorkflowActions,
  useWorkflowState,
  useWorkflowStoreContext,
} from '../hooks/useWorkflow';
import { notifications } from '../lib/notifications';

import { CollaborativeWorkflowDiagram } from './diagram/CollaborativeWorkflowDiagram';
import { FullScreenIDE } from './ide/FullScreenIDE';
import { Inspector } from './inspector';
import { LeftPanel } from './left-panel';
import { ManualRunPanel } from './ManualRunPanel';
import { ManualRunPanelErrorBoundary } from './ManualRunPanelErrorBoundary';

interface WorkflowEditorProps {
  parentProjectId?: string | null;
  parentProjectName?: string | null;
}

export function WorkflowEditor({
  parentProjectId,
  parentProjectName,
}: WorkflowEditorProps = {}) {
  const { searchParams, updateSearchParams } = useURLState();
  const { currentNode, selectNode } = useNodeSelection();
  const workflowStore = useWorkflowStoreContext();
  const isNewWorkflow = useIsNewWorkflow();
  const { saveWorkflow } = useWorkflowActions();

  const isRunPanelOpen = useIsRunPanelOpen();
  const runPanelContext = useRunPanelContext();
  const { closeRunPanel, openRunPanel } = useUICommands();

  const isSyncingRef = useRef(false);
  const isInitialMountRef = useRef(true);

  useEffect(() => {
    if (isSyncingRef.current) return;

    const panelParam = searchParams.get('panel');

    if (isRunPanelOpen) {
      const contextJobId = runPanelContext?.jobId;
      const contextTriggerId = runPanelContext?.triggerId;
      const needsUpdate = panelParam !== 'run';

      if (needsUpdate) {
        isSyncingRef.current = true;
        if (contextJobId) {
          updateSearchParams({
            panel: 'run',
            job: contextJobId,
            trigger: null,
          });
        } else if (contextTriggerId) {
          updateSearchParams({
            panel: 'run',
            trigger: contextTriggerId,
            job: null,
          });
        } else {
          updateSearchParams({ panel: 'run' });
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
      updateSearchParams({ panel: null });
      setTimeout(() => {
        isSyncingRef.current = false;
      }, 0);
    }
  }, [isRunPanelOpen, runPanelContext, searchParams, updateSearchParams]);

  useEffect(() => {
    const panelParam = searchParams.get('panel');

    if (panelParam === 'run' && !isRunPanelOpen) {
      isSyncingRef.current = true;

      const jobParam = searchParams.get('job');
      const triggerParam = searchParams.get('trigger');

      if (jobParam) {
        openRunPanel({ jobId: jobParam });
      } else if (triggerParam) {
        openRunPanel({ triggerId: triggerParam });
      } else if (currentNode.type === 'job' && currentNode.node) {
        openRunPanel({ jobId: currentNode.node.id });
      } else if (currentNode.type === 'trigger' && currentNode.node) {
        openRunPanel({ triggerId: currentNode.node.id });
      } else {
        const firstTrigger = workflow.triggers[0];
        if (firstTrigger?.id) {
          openRunPanel({ triggerId: firstTrigger.id });
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
    searchParams,
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

  const [showLeftPanel, setShowLeftPanel] = useState(isNewWorkflow);

  const workflow = useWorkflowState(state => ({
    ...state.workflow!,
    jobs: state.jobs,
    triggers: state.triggers,
    edges: state.edges,
    positions: state.positions,
  }));

  const currentMethod = searchParams.get('method') as
    | 'template'
    | 'import'
    | 'ai'
    | null;

  const leftPanelMethod = showLeftPanel ? currentMethod || 'template' : null;

  const isIDEOpen = searchParams.get('panel') === 'editor';
  const selectedJobId = searchParams.get('job');

  const handleCloseInspector = () => {
    selectNode(null);
  };

  const showInspector =
    searchParams.get('panel') === 'settings' ||
    searchParams.get('panel') === 'code' ||
    Boolean(currentNode.node);

  const handleMethodChange = (method: 'template' | 'import' | 'ai' | null) => {
    updateSearchParams({ method });
  };

  const handleImport = async (workflowState: YAMLWorkflowState) => {
    try {
      const validatedState =
        await workflowStore.validateWorkflowName(workflowState);

      workflowStore.importWorkflow(validatedState);
    } catch (error) {
      console.error('Failed to validate workflow name:', error);
      workflowStore.importWorkflow(workflowState);
    }
  };

  const handleCloseLeftPanel = () => {
    setShowLeftPanel(false);
    updateSearchParams({ method: null });
  };

  const handleSaveAndClose = async () => {
    await saveWorkflow();
    handleCloseLeftPanel();
  };

  const handleCloseIDE = () => {
    updateSearchParams({ panel: null });
  };

  // Open Code Editor with Cmd+E / Ctrl+E
  useKeyboardShortcut(
    'Control+e, Meta+e',
    () => {
      if (currentNode.type !== 'job' || !currentNode.node) {
        return;
      }

      updateSearchParams({ panel: 'editor' });
    },
    0, // GLOBAL priority
    {
      enabled: !isIDEOpen,
    }
  );

  // CMD+Enter: Open run panel or run workflow
  useKeyboardShortcut(
    'Control+Enter, Meta+Enter',
    () => {
      // If run panel is already open, let the ManualRunPanel handle it
      if (isRunPanelOpen) {
        return;
      }

      // Open run panel based on current selection
      if (currentNode.type === 'job' && currentNode.node) {
        openRunPanel({ jobId: currentNode.node.id });
      } else if (currentNode.type === 'trigger' && currentNode.node) {
        openRunPanel({ triggerId: currentNode.node.id });
      } else {
        // No selection - open from first trigger
        const firstTrigger = workflow.triggers[0];
        if (firstTrigger?.id) {
          openRunPanel({ triggerId: firstTrigger.id });
        }
      }
    },
    0, // GLOBAL priority
    {
      enabled: !isIDEOpen && !isRunPanelOpen,
    }
  );

  return (
    <div className="relative flex h-full w-full">
      <div
        className={`flex-1 relative transition-all duration-300 ease-in-out ${
          showLeftPanel ? 'ml-[33.333333%]' : 'ml-0'
        }`}
      >
        <CollaborativeWorkflowDiagram inspectorId="inspector" />

        {!isRunPanelOpen && (
          <div
            id="inspector"
            className={`absolute top-0 right-0 transition-transform duration-300 ease-in-out z-10 ${
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
          <div className="absolute inset-y-0 right-0 flex pointer-events-none z-20">
            <ManualRunPanelErrorBoundary onClose={closeRunPanel}>
              <ManualRunPanel
                workflow={workflow}
                projectId={projectId}
                workflowId={workflowId}
                jobId={runPanelContext.jobId ?? null}
                triggerId={runPanelContext.triggerId ?? null}
                edgeId={runPanelContext.edgeId ?? null}
                onClose={closeRunPanel}
                saveWorkflow={saveWorkflow}
              />
            </ManualRunPanelErrorBoundary>
          </div>
        )}
      </div>

      <LeftPanel
        method={leftPanelMethod}
        onMethodChange={handleMethodChange}
        onImport={handleImport}
        onClosePanel={handleCloseLeftPanel}
        onSave={handleSaveAndClose}
      />

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
