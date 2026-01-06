/**
 * WorkflowEditor - Main workflow editing component
 */

import { useCallback, useEffect, useRef } from 'react';

import { useURLState } from '#/react/lib/use-url-state';
import { cn } from '#/utils/cn';

import type { WorkflowState as YAMLWorkflowState } from '../../yaml/types';
import { useResizablePanel } from '../hooks/useResizablePanel';
import { useIsNewWorkflow, useProject } from '../hooks/useSessionContext';
import {
  useIsRunPanelOpen,
  useRunPanelContext,
  useTemplatePanel,
  useUICommands,
  useIsCreateWorkflowPanelCollapsed,
  useIsAIAssistantPanelOpen,
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
import { LeftPanel } from './left-panel';
import { ManualRunPanel } from './ManualRunPanel';
import { ManualRunPanelErrorBoundary } from './ManualRunPanelErrorBoundary';
import { TemplateDetailsCard } from './TemplateDetailsCard';
import { Tooltip } from './Tooltip';
import { useUnsavedChanges } from '../hooks/useUnsavedChanges';

interface WorkflowEditorProps {
  parentProjectId?: string | null;
  parentProjectName?: string | null;
}

export function WorkflowEditor({
  parentProjectId = null,
  parentProjectName = null,
}: WorkflowEditorProps = {}) {
  useUnsavedChanges();
  const { params, updateSearchParams } = useURLState();
  const { currentNode, selectNode } = useNodeSelection();
  const workflowStore = useWorkflowStoreContext();
  const isNewWorkflow = useIsNewWorkflow();
  const { saveWorkflow } = useWorkflowActions();

  const isRunPanelOpen = useIsRunPanelOpen();
  const runPanelContext = useRunPanelContext();
  const {
    closeRunPanel,
    openRunPanel,
    toggleCreateWorkflowPanel,
    openAIAssistantPanel,
    closeAIAssistantPanel,
    collapseCreateWorkflowPanel,
    expandCreateWorkflowPanel,
    setTemplateSearchQuery,
  } = useUICommands();
  const isCreateWorkflowPanelCollapsed = useIsCreateWorkflowPanelCollapsed();
  const isAIAssistantPanelOpen = useIsAIAssistantPanelOpen();

  // Get selected template from UI store (for template details card)
  const { selectedTemplate } = useTemplatePanel();

  // Check if viewing a pinned version (not latest) to disable AI Assistant
  const isPinnedVersion = params['v'] !== undefined && params['v'] !== null;

  const isSyncingRef = useRef(false);
  const isInitialMountRef = useRef(true);

  useEffect(() => {
    if (isSyncingRef.current) return;

    const panelParam = params['panel'] ?? null;

    if (isRunPanelOpen) {
      const contextJobId = runPanelContext?.jobId;
      const contextTriggerId = runPanelContext?.triggerId;

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
  }, [isRunPanelOpen, runPanelContext, params, updateSearchParams]);

  useEffect(() => {
    const panelParam = params['panel'] ?? null;

    if (panelParam === 'run' && !isRunPanelOpen) {
      isSyncingRef.current = true;

      const jobParam = params['job'] ?? null;
      const triggerParam = params['trigger'] ?? null;

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

  const {
    width: leftPanelWidth,
    isResizing: isResizingLeft,
    handleMouseDown: handleMouseDownLeft,
  } = useResizablePanel({
    storageKey: 'left-panel-width',
    defaultWidth: 400,
    direction: 'right',
  });

  const workflow = useWorkflowState(state => ({
    ...state.workflow!,
    jobs: state.jobs,
    triggers: state.triggers,
    edges: state.edges,
    positions: state.positions,
  }));

  const currentMethod = (params['method'] ?? null) as
    | 'template'
    | 'import'
    | 'ai'
    | null;

  const leftPanelMethod = currentMethod || 'template';

  // Clear template URL params when panel collapses
  const prevPanelCollapsedRef = useRef(isCreateWorkflowPanelCollapsed);
  useEffect(() => {
    const wasExpanded = !prevPanelCollapsedRef.current;
    const isNowCollapsed = isCreateWorkflowPanelCollapsed;

    if (wasExpanded && isNowCollapsed) {
      // Panel just collapsed - clear template URL params
      updateSearchParams({ template: null, search: null });
    }

    prevPanelCollapsedRef.current = isCreateWorkflowPanelCollapsed;
  }, [isCreateWorkflowPanelCollapsed, updateSearchParams]);

  // Clear template params when in import/ai mode (handles page refresh)
  useEffect(() => {
    const templateParam = params['template'];
    const searchParam = params['search'];

    if (
      (leftPanelMethod === 'import' || leftPanelMethod === 'ai') &&
      (templateParam || searchParam)
    ) {
      updateSearchParams({ template: null, search: null });
    }
  }, [leftPanelMethod, params, updateSearchParams]);

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

  /**
   * Consolidated canvas clearing effect for new workflows.
   *
   * Clears the canvas when:
   * 1. AI Assistant panel opens (to prepare for AI-generated workflow)
   * 2. User switches between template/import methods while panel is open
   * 3. Both panels transition to closed (user collapses the last open panel)
   *
   * Note: Uses refs to track previous state and only clear on actual transitions,
   * not on initial mount or when both panels are already closed.
   */
  const prevAIPanelOpenRef = useRef(isAIAssistantPanelOpen);
  const prevMethodRef = useRef(leftPanelMethod);
  const prevCreatePanelCollapsedRef = useRef(isCreateWorkflowPanelCollapsed);
  const hasInitializedRef = useRef(false);

  useEffect(() => {
    // Skip clearing on initial mount - let URL state restoration handle it
    if (!hasInitializedRef.current) {
      hasInitializedRef.current = true;
      prevAIPanelOpenRef.current = isAIAssistantPanelOpen;
      prevMethodRef.current = leftPanelMethod;
      prevCreatePanelCollapsedRef.current = isCreateWorkflowPanelCollapsed;
      return;
    }

    if (!isNewWorkflow) {
      // Update refs but don't clear for existing workflows
      prevAIPanelOpenRef.current = isAIAssistantPanelOpen;
      prevMethodRef.current = leftPanelMethod;
      prevCreatePanelCollapsedRef.current = isCreateWorkflowPanelCollapsed;
      return;
    }

    const aiPanelJustOpened =
      !prevAIPanelOpenRef.current && isAIAssistantPanelOpen;
    const methodChanged =
      !isCreateWorkflowPanelCollapsed &&
      prevMethodRef.current !== leftPanelMethod;

    // Only clear when TRANSITIONING to both-closed state, not when already closed
    const wasAnyPanelOpen =
      prevAIPanelOpenRef.current || !prevCreatePanelCollapsedRef.current;
    const bothNowClosed =
      isCreateWorkflowPanelCollapsed && !isAIAssistantPanelOpen;
    const bothPanelsJustClosed = wasAnyPanelOpen && bothNowClosed;

    // Clear canvas on any of these transitions
    if (aiPanelJustOpened || methodChanged || bothPanelsJustClosed) {
      clearCanvas();
    }

    // Update refs for next comparison
    prevAIPanelOpenRef.current = isAIAssistantPanelOpen;
    prevMethodRef.current = leftPanelMethod;
    prevCreatePanelCollapsedRef.current = isCreateWorkflowPanelCollapsed;
  }, [
    isAIAssistantPanelOpen,
    isNewWorkflow,
    leftPanelMethod,
    isCreateWorkflowPanelCollapsed,
    clearCanvas,
  ]);

  // Sync method to URL (similar to AI panel's chat param sync)
  const isSyncingMethodRef = useRef(false);
  useEffect(() => {
    if (isSyncingMethodRef.current) return;

    isSyncingMethodRef.current = true;
    updateSearchParams({
      method: isCreateWorkflowPanelCollapsed ? null : leftPanelMethod,
    });
    setTimeout(() => {
      isSyncingMethodRef.current = false;
    }, 0);
  }, [isCreateWorkflowPanelCollapsed, leftPanelMethod, updateSearchParams]);

  const isIDEOpen = params['panel'] === 'editor';
  const selectedJobId = params['job'] ?? null;

  const handleCloseIDE = useCallback(() => {
    updateSearchParams({ panel: null });
  }, [updateSearchParams]);

  const handleCloseInspector = () => {
    selectNode(null);
  };

  const showInspector =
    params['panel'] === 'settings' ||
    params['panel'] === 'code' ||
    params['panel'] === 'publish-template' ||
    Boolean(currentNode.node);

  const handleMethodChange = (method: 'template' | 'import' | 'ai' | null) => {
    // Always clear template URL params when switching methods - start fresh each time
    updateSearchParams({ method, template: null, search: null });
  };

  /**
   * Imports a workflow state into the canvas.
   *
   * This function validates the workflow name to ensure uniqueness, then imports
   * the workflow. If validation fails, it still imports the workflow (the server
   * will handle name conflicts on save).
   *
   * Note: This is intentionally synchronous from the caller's perspective.
   * The async validation happens in the background, but import proceeds
   * immediately after validation completes or fails.
   */
  const handleImport = useCallback(
    (workflowState: YAMLWorkflowState) => {
      // Validate workflow name asynchronously, but proceed with import regardless
      workflowStore
        .validateWorkflowName(workflowState)
        .then(validatedState => {
          workflowStore.importWorkflow(validatedState);
        })
        .catch((error: unknown) => {
          // If validation fails, import with original state
          // Server will handle any name conflicts on save
          console.warn('Workflow name validation failed, proceeding:', error);
          workflowStore.importWorkflow(workflowState);
        });
    },
    [workflowStore]
  );

  const handleSaveAndClose = async () => {
    await saveWorkflow();
    collapseCreateWorkflowPanel();
  };

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

  /**
   * Keyboard shortcuts for new workflow creation panels.
   *
   * These shortcuts only work when creating a new workflow (isNewWorkflow=true):
   * - Cmd/Ctrl + / : Toggle template panel (template browsing mode)
   * - Cmd/Ctrl + \ : Toggle import panel (YAML import mode)
   * - Cmd/Ctrl + K : Toggle AI Assistant (handled in AIAssistantPanelWrapper)
   *
   * Note: Using comma-separated combos for cross-platform support.
   * "Control+/" handles Windows/Linux, "Meta+/" handles macOS.
   * The tinykeys library parses these and binds to the appropriate key.
   */
  useKeyboardShortcut(
    'Control+/, Meta+/',
    () => {
      if (!isNewWorkflow) return;

      if (leftPanelMethod === 'template' && !isCreateWorkflowPanelCollapsed) {
        // Already open in template mode - collapse it
        collapseCreateWorkflowPanel();
      } else {
        // Close AI Assistant panel when expanding create panel
        if (isAIAssistantPanelOpen) {
          closeAIAssistantPanel();
        }
        // Open in template mode
        handleMethodChange('template');
        if (isCreateWorkflowPanelCollapsed) {
          expandCreateWorkflowPanel();
        }
      }
    },
    0,
    {
      enabled: isNewWorkflow,
    }
  );

  // Cmd/Ctrl+\ to toggle import panel (see JSDoc above for full shortcut docs)
  useKeyboardShortcut(
    'Control+\\, Meta+\\',
    () => {
      if (!isNewWorkflow) return;

      if (leftPanelMethod === 'import' && !isCreateWorkflowPanelCollapsed) {
        // Already open in import mode - collapse it
        collapseCreateWorkflowPanel();
      } else {
        // Close AI Assistant panel when expanding create panel
        if (isAIAssistantPanelOpen) {
          closeAIAssistantPanel();
        }
        // Open in import mode
        handleMethodChange('import');
        if (isCreateWorkflowPanelCollapsed) {
          expandCreateWorkflowPanel();
        }
      }
    },
    0,
    {
      enabled: isNewWorkflow,
    }
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
      {/* Create Workflow Panel - Always rendered for smooth animations */}
      {isNewWorkflow && (
        <div
          className="flex h-full flex-shrink-0"
          style={{
            zIndex: Z_INDEX.SIDE_PANEL,
            width: !isCreateWorkflowPanelCollapsed
              ? `${leftPanelWidth}px`
              : '0px',
            overflow: 'hidden',
            transition: isResizingLeft
              ? 'none'
              : 'width 0.4s cubic-bezier(0.4, 0, 0.2, 1)',
          }}
        >
          {!isCreateWorkflowPanelCollapsed && (
            <>
              <div className="flex-1 overflow-hidden">
                <LeftPanel
                  method={leftPanelMethod}
                  onMethodChange={handleMethodChange}
                  onImport={handleImport}
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
        </div>
      )}
      {/* Toggle button when collapsed */}
      {isNewWorkflow && isCreateWorkflowPanelCollapsed && (
        <Tooltip content="Open the create workflow panel (⌘+/)" side="right">
          <button
            type="button"
            onClick={() => {
              // Close AI Assistant panel when expanding create panel
              if (isAIAssistantPanelOpen) {
                closeAIAssistantPanel();
              }
              toggleCreateWorkflowPanel();
            }}
            style={{ zIndex: Z_INDEX.SIDE_PANEL_TOGGLE }}
            className="absolute left-0 top-6 bg-white border border-gray-200 rounded-r-md p-1 shadow-sm hover:bg-gray-50 transition-colors"
            aria-label="Expand create workflow panel"
          >
            <span className="hero-chevron-right h-4 w-4 text-gray-600" />
          </button>
        </Tooltip>
      )}

      <div className="flex-1 relative">
        <CollaborativeWorkflowDiagram inspectorId="inspector" />

        {/* Show placeholder when workflow is empty */}
        {isNewWorkflow &&
          workflow.jobs.length === 0 &&
          workflow.triggers.length === 0 && (
            <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
              <div className="text-center max-w-3xl px-6 pointer-events-auto">
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

                <div className="grid grid-cols-3 gap-4 items-start">
                  <button
                    type="button"
                    onClick={() => {
                      // Toggle create panel in template mode
                      if (
                        leftPanelMethod === 'template' &&
                        !isCreateWorkflowPanelCollapsed
                      ) {
                        // Already open in template mode - collapse it
                        collapseCreateWorkflowPanel();
                      } else {
                        // Close AI if open
                        if (isAIAssistantPanelOpen) {
                          closeAIAssistantPanel();
                        }
                        // Open in template mode
                        handleMethodChange('template');
                        // Clear search
                        setTemplateSearchQuery('');
                        updateSearchParams({ search: null });
                        if (isCreateWorkflowPanelCollapsed) {
                          expandCreateWorkflowPanel();
                        }
                      }
                    }}
                    className={`group flex flex-col items-center text-center bg-white border rounded-xl p-5 transition-all duration-200 cursor-pointer ${
                      leftPanelMethod === 'template' &&
                      !isCreateWorkflowPanelCollapsed
                        ? 'border-primary-500 ring-2 ring-primary-100 shadow-sm'
                        : 'border-gray-200 hover:border-primary-300 hover:shadow-sm'
                    }`}
                  >
                    <div className="inline-flex items-center justify-center w-12 h-12 rounded-xl bg-primary-50 group-hover:bg-primary-100 mb-4 transition-colors">
                      <span className="hero-document-text h-6 w-6 text-primary-600" />
                    </div>
                    <h4 className="text-sm font-semibold text-gray-900 mb-1.5 whitespace-nowrap">
                      Browse templates
                    </h4>
                    <p className="text-xs text-gray-500 leading-relaxed">
                      Start from published templates
                    </p>
                  </button>

                  <Tooltip
                    content={
                      isPinnedVersion
                        ? 'Switch to the latest version of this workflow to use the AI Assistant.'
                        : isAIAssistantPanelOpen
                          ? 'Close AI Assistant'
                          : 'Generate with AI'
                    }
                    side="top"
                  >
                    <button
                      type="button"
                      onClick={() => {
                        // Toggle AI Assistant panel
                        if (isAIAssistantPanelOpen) {
                          closeAIAssistantPanel();
                        } else {
                          // Close create panel if open
                          if (!isCreateWorkflowPanelCollapsed) {
                            collapseCreateWorkflowPanel();
                          }
                          openAIAssistantPanel();
                        }
                      }}
                      disabled={isPinnedVersion}
                      className={`group flex flex-col items-center text-center bg-white border rounded-xl p-5 transition-all duration-200 ${
                        isPinnedVersion
                          ? 'cursor-not-allowed opacity-50'
                          : `cursor-pointer ${
                              isAIAssistantPanelOpen
                                ? 'border-primary-500 ring-2 ring-primary-100 shadow-sm'
                                : 'border-gray-200 hover:border-primary-300 hover:shadow-sm'
                            }`
                      }`}
                    >
                      <div
                        className={cn(
                          'inline-flex items-center justify-center w-12 h-12 rounded-xl bg-primary-50 mb-4 transition-colors',
                          !isPinnedVersion && 'group-hover:bg-primary-100'
                        )}
                      >
                        <span className="hero-sparkles h-6 w-6 text-primary-600" />
                      </div>
                      <h4 className="text-sm font-semibold text-gray-900 mb-1.5 whitespace-nowrap">
                        Generate with AI
                      </h4>
                      <p className="text-xs text-gray-500 leading-relaxed">
                        Build custom workflows with AI
                      </p>
                    </button>
                  </Tooltip>

                  <button
                    type="button"
                    onClick={() => {
                      // Toggle create panel in import mode
                      if (
                        leftPanelMethod === 'import' &&
                        !isCreateWorkflowPanelCollapsed
                      ) {
                        // Already open in import mode - collapse it
                        collapseCreateWorkflowPanel();
                      } else {
                        // Close AI if open
                        if (isAIAssistantPanelOpen) {
                          closeAIAssistantPanel();
                        }
                        // Open in import mode
                        handleMethodChange('import');
                        if (isCreateWorkflowPanelCollapsed) {
                          expandCreateWorkflowPanel();
                        }
                      }
                    }}
                    className={`group flex flex-col items-center text-center bg-white border rounded-xl p-5 transition-all duration-200 cursor-pointer ${
                      leftPanelMethod === 'import' &&
                      !isCreateWorkflowPanelCollapsed
                        ? 'border-primary-500 ring-2 ring-primary-100 shadow-sm'
                        : 'border-gray-200 hover:border-primary-300 hover:shadow-sm'
                    }`}
                  >
                    <div className="inline-flex items-center justify-center w-12 h-12 rounded-xl bg-primary-50 group-hover:bg-primary-100 mb-4 transition-colors">
                      <span className="hero-document-arrow-up h-6 w-6 text-primary-600" />
                    </div>
                    <h4 className="text-sm font-semibold text-gray-900 mb-1.5 whitespace-nowrap">
                      Import workflow
                    </h4>
                    <p className="text-xs text-gray-500 leading-relaxed">
                      Upload or paste workflow code
                    </p>
                  </button>
                </div>
              </div>
            </div>
          )}

        {/* Show template details card when a template is selected */}
        {!isCreateWorkflowPanelCollapsed &&
          leftPanelMethod === 'template' &&
          selectedTemplate && (
            <TemplateDetailsCard template={selectedTemplate} />
          )}

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
