/**
 * WorkflowEditor - Main workflow editing component
 */

import {
  useContext,
  useEffect,
  useRef,
  useState,
  useSyncExternalStore,
} from 'react';

import { useURLState } from '../../react/lib/use-url-state';
import type { WorkflowState as YAMLWorkflowState } from '../../yaml/types';
import { StoreContext } from '../contexts/StoreProvider';
import { useIsNewWorkflow, useProject } from '../hooks/useSessionContext';
import {
  useIsRunPanelOpen,
  useRunPanelContext,
  useUICommands,
} from '../hooks/useUI';
import {
  useNodeSelection,
  useWorkflowActions,
  useWorkflowState,
  useWorkflowStoreContext,
} from '../hooks/useWorkflow';
import { useKeyboardShortcut } from '../keyboard';

import { CollaborativeWorkflowDiagram } from './diagram/CollaborativeWorkflowDiagram';
import { Inspector } from './inspector';
import { LeftPanel } from './left-panel';
import { ManualRunPanel } from './ManualRunPanel';
import { ManualRunPanelErrorBoundary } from './ManualRunPanelErrorBoundary';
import { TemplateDetailsCard } from './TemplateDetailsCard';

export function WorkflowEditor() {
  const { searchParams, updateSearchParams } = useURLState();
  const { currentNode, selectNode } = useNodeSelection();
  const workflowStore = useWorkflowStoreContext();
  const isNewWorkflow = useIsNewWorkflow();
  const { saveWorkflow } = useWorkflowActions();

  const isRunPanelOpen = useIsRunPanelOpen();
  const runPanelContext = useRunPanelContext();
  const { closeRunPanel, openRunPanel } = useUICommands();

  // Get selected template from UI store
  const context = useContext(StoreContext);
  const selectedTemplate = context
    ? useSyncExternalStore(
        context.uiStore.subscribe,
        context.uiStore.withSelector(
          state => state.templatePanel.selectedTemplate
        )
      )
    : null;

  const isSyncingRef = useRef(false);
  const isInitialMountRef = useRef(true);

  useEffect(() => {
    if (isSyncingRef.current) return;

    const panelParam = searchParams.get('panel');

    if (isRunPanelOpen) {
      const contextJobId = runPanelContext?.jobId;
      const contextTriggerId = runPanelContext?.triggerId;
      // Don't override settings, code, or editor panels when user explicitly opens them
      const isSpecialPanel = ['settings', 'code', 'editor'].includes(
        panelParam || ''
      );
      const needsUpdate = panelParam !== 'run' && !isSpecialPanel;

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
  const [leftPanelWidth, setLeftPanelWidth] = useState(() => {
    const saved = localStorage.getItem('left-panel-width');
    return saved ? parseInt(saved, 10) : 400;
  });
  const [isResizingLeft, setIsResizingLeft] = useState(false);
  const startXLeftRef = useRef<number>(0);
  const startWidthLeftRef = useRef<number>(0);

  useEffect(() => {
    if (!isNewWorkflow && showLeftPanel) {
      setShowLeftPanel(false);
    }
  }, [isNewWorkflow, showLeftPanel]);

  useEffect(() => {
    if (!isResizingLeft) return;

    const handleMouseMove = (e: MouseEvent) => {
      const deltaX = e.clientX - startXLeftRef.current;
      const viewportWidth = window.innerWidth;
      const minWidth = Math.max(300, viewportWidth * 0.2); // 20% or 300px, whichever is larger
      const maxWidth = Math.min(600, viewportWidth * 0.4); // 40% or 600px, whichever is smaller
      const newWidth = Math.max(
        minWidth,
        Math.min(maxWidth, startWidthLeftRef.current + deltaX)
      );
      setLeftPanelWidth(newWidth);
    };

    const handleMouseUp = () => {
      setIsResizingLeft(false);
      localStorage.setItem('left-panel-width', leftPanelWidth.toString());
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);

    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isResizingLeft, leftPanelWidth]);

  const handleMouseDownLeft = (e: React.MouseEvent) => {
    e.preventDefault();
    startXLeftRef.current = e.clientX;
    startWidthLeftRef.current = leftPanelWidth;
    setIsResizingLeft(true);
  };

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

  const handleCloseInspector = () => {
    selectNode(null);
  };

  const showInspector =
    searchParams.get('panel') === 'settings' ||
    searchParams.get('panel') === 'code' ||
    searchParams.get('panel') === 'publish-template' ||
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

  const isIDEOpen = searchParams.get('panel') === 'editor';

  useKeyboardShortcut(
    'Control+Enter, Meta+Enter',
    () => {
      if (isRunPanelOpen) {
        return;
      }

      if (currentNode.type === 'job' && currentNode.node) {
        openRunPanel({ jobId: currentNode.node.id });
      } else if (currentNode.type === 'trigger' && currentNode.node) {
        openRunPanel({ triggerId: currentNode.node.id });
      } else {
        const firstTrigger = workflow.triggers[0];
        if (firstTrigger?.id) {
          openRunPanel({ triggerId: firstTrigger.id });
        }
      }
    },
    0,
    {
      enabled: !isIDEOpen && !isRunPanelOpen,
    }
  );

  return (
    <div className="flex h-full w-full">
      {showLeftPanel && (
        <>
          <div
            className="flex-shrink-0"
            style={{
              width: `${leftPanelWidth}px`,
              transition: isResizingLeft ? 'none' : 'width 0.2s ease',
            }}
          >
            <LeftPanel
              method={leftPanelMethod}
              onMethodChange={handleMethodChange}
              onImport={handleImport}
              onClosePanel={handleCloseLeftPanel}
              onSave={handleSaveAndClose}
            />
          </div>
          <button
            type="button"
            className="w-1 bg-gray-200 hover:bg-primary-500 transition-colors cursor-col-resize flex-shrink-0"
            onMouseDown={handleMouseDownLeft}
            aria-label="Resize left panel"
          />
        </>
      )}

      <div className="flex-1 relative">
        <CollaborativeWorkflowDiagram inspectorId="inspector" />

        {/* Show template placeholder when panel is open but no template selected and workflow is empty */}
        {showLeftPanel &&
          leftPanelMethod === 'template' &&
          !selectedTemplate &&
          workflow.jobs.length === 0 &&
          workflow.triggers.length === 0 && (
            <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
              <div className="text-center max-w-lg px-6">
                <div className="inline-flex items-center justify-center mb-6">
                  <img
                    src="/images/logo.svg"
                    alt="OpenFn"
                    className="w-20 h-20 opacity-20"
                  />
                </div>
                <h3 className="text-lg font-semibold text-gray-900 mb-3">
                  Create your workflow
                </h3>
                <p className="text-sm text-gray-600 mb-6">
                  Choose how you'd like to get started with your new workflow
                </p>

                <div className="grid grid-cols-3 gap-6">
                  <div className="text-center">
                    <div className="inline-flex items-center justify-center w-10 h-10 rounded-full bg-primary-100 mb-3">
                      <span className="hero-document-text h-5 w-5 text-primary-600" />
                    </div>
                    <h4 className="text-sm font-medium text-gray-900 mb-2">
                      Browse templates
                    </h4>
                    <p className="text-xs text-gray-500">
                      Browse pre-built templates and search by name or tags
                    </p>
                  </div>

                  <div className="text-center">
                    <div className="inline-flex items-center justify-center w-10 h-10 rounded-full bg-primary-100 mb-3">
                      <span className="hero-sparkles h-5 w-5 text-primary-600" />
                    </div>
                    <h4 className="text-sm font-medium text-gray-900 mb-2">
                      Generate with AI
                    </h4>
                    <p className="text-xs text-gray-500">
                      Use AI to generate custom workflows based on your needs
                    </p>
                  </div>

                  <div className="text-center">
                    <div className="inline-flex items-center justify-center w-10 h-10 rounded-full bg-primary-100 mb-3">
                      <span className="hero-document-arrow-up h-5 w-5 text-primary-600" />
                    </div>
                    <h4 className="text-sm font-medium text-gray-900 mb-2">
                      Import YAML
                    </h4>
                    <p className="text-xs text-gray-500">
                      Import existing workflows from YAML files or text
                    </p>
                  </div>
                </div>
              </div>
            </div>
          )}

        {/* Show template details card when a template is selected */}
        {showLeftPanel &&
          leftPanelMethod === 'template' &&
          selectedTemplate && (
            <TemplateDetailsCard template={selectedTemplate} />
          )}

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
    </div>
  );
}
