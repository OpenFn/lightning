/**
 * WorkflowEditor - Main workflow editing component
 */

import { useCallback, useEffect, useRef, useState } from 'react';

import { useURLState } from '../../react/lib/use-url-state';
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

import { CollaborativeWorkflowDiagram } from './diagram/CollaborativeWorkflowDiagram';
import { Inspector } from './inspector';
import { LeftPanel } from './left-panel';
import { ManualRunPanel } from './ManualRunPanel';
import { ManualRunPanelErrorBoundary } from './ManualRunPanelErrorBoundary';
import { TemplateDetailsCard } from './TemplateDetailsCard';
import { Tooltip } from './Tooltip';

export function WorkflowEditor() {
  const { searchParams, updateSearchParams } = useURLState();
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
    selectTemplate,
    setTemplateSearchQuery,
  } = useUICommands();
  const isCreateWorkflowPanelCollapsed = useIsCreateWorkflowPanelCollapsed();
  const isAIAssistantPanelOpen = useIsAIAssistantPanelOpen();

  // Get selected template from UI store using Stuart's refactored hook
  const { selectedTemplate } = useTemplatePanel();

  // Save/restore selected template using localStorage
  useEffect(() => {
    if (isCreateWorkflowPanelCollapsed && selectedTemplate) {
      // Save template to localStorage when panel closes
      try {
        localStorage.setItem(
          'lastSelectedTemplate',
          JSON.stringify(selectedTemplate)
        );
      } catch (error) {
        console.warn('Failed to save template to localStorage:', error);
      }

      // Clear from store
      selectTemplate(null);
    }
  }, [isCreateWorkflowPanelCollapsed, selectedTemplate, selectTemplate]);

  // Clear template-related URL params when panel collapses
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

  const currentMethod = searchParams.get('method') as
    | 'template'
    | 'import'
    | 'ai'
    | null;

  const leftPanelMethod = currentMethod || 'template';

  // Clear template params when in import/ai mode (handles page refresh)
  useEffect(() => {
    const templateParam = searchParams.get('template');
    const searchParam = searchParams.get('search');

    if (
      (leftPanelMethod === 'import' || leftPanelMethod === 'ai') &&
      (templateParam || searchParam)
    ) {
      updateSearchParams({ template: null, search: null });
    }
  }, [leftPanelMethod, searchParams, updateSearchParams]);

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

      // Remove all triggers by clearing the array directly
      // Access ydoc through the store's internal structure
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const storeWithYdoc = workflowStore as any;
      if (storeWithYdoc.ydoc) {
        const triggersArray = storeWithYdoc.ydoc.getArray('triggers');
        storeWithYdoc.ydoc.transact(() => {
          triggersArray.delete(0, triggersArray.length);
        });
      }
    }
  }, [workflow.jobs, workflow.triggers, workflow.edges, workflowStore]);

  // Clear canvas when AI Assistant opens (only on the transition from closed to open)
  const prevAIPanelOpenRef = useRef(isAIAssistantPanelOpen);
  useEffect(() => {
    const wasJustOpened = !prevAIPanelOpenRef.current && isAIAssistantPanelOpen;
    if (wasJustOpened && isNewWorkflow) {
      clearCanvas();
    }
    prevAIPanelOpenRef.current = isAIAssistantPanelOpen;
  }, [isAIAssistantPanelOpen, isNewWorkflow, clearCanvas]);

  // Clear canvas when switching between template and import methods
  const prevMethodRef = useRef(leftPanelMethod);
  useEffect(() => {
    if (
      !isCreateWorkflowPanelCollapsed &&
      isNewWorkflow &&
      prevMethodRef.current !== leftPanelMethod
    ) {
      clearCanvas();
    }
    prevMethodRef.current = leftPanelMethod;
  }, [
    leftPanelMethod,
    isCreateWorkflowPanelCollapsed,
    isNewWorkflow,
    clearCanvas,
  ]);

  // Clear canvas when both create panel and AI panel are closed
  useEffect(() => {
    if (
      isCreateWorkflowPanelCollapsed &&
      !isAIAssistantPanelOpen &&
      isNewWorkflow
    ) {
      clearCanvas();
    }
  }, [
    isCreateWorkflowPanelCollapsed,
    isAIAssistantPanelOpen,
    isNewWorkflow,
    clearCanvas,
  ]);

  // Restore selected template when reopening in template mode
  useEffect(() => {
    if (
      !isCreateWorkflowPanelCollapsed &&
      leftPanelMethod === 'template' &&
      !selectedTemplate
    ) {
      try {
        const saved = localStorage.getItem('lastSelectedTemplate');
        if (saved) {
          const templateToRestore = JSON.parse(
            saved
          ) as typeof selectedTemplate;
          localStorage.removeItem('lastSelectedTemplate'); // Clear after restoring
          selectTemplate(templateToRestore);
          updateSearchParams({ template: templateToRestore?.id ?? null });
        }
      } catch (error) {
        console.warn('Failed to restore template from localStorage:', error);
      }
    }
  }, [
    isCreateWorkflowPanelCollapsed,
    leftPanelMethod,
    selectedTemplate,
    selectTemplate,
    updateSearchParams,
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

  const handleCloseInspector = () => {
    selectNode(null);
  };

  const showInspector =
    searchParams.get('panel') === 'settings' ||
    searchParams.get('panel') === 'code' ||
    searchParams.get('panel') === 'publish-template' ||
    Boolean(currentNode.node);

  const handleMethodChange = (method: 'template' | 'import' | 'ai' | null) => {
    // When switching to import/ai mode, clear template params
    if (method === 'import' || method === 'ai') {
      updateSearchParams({ method, template: null, search: null });
    } else {
      updateSearchParams({ method });
    }
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

  const handleSaveAndClose = async () => {
    await saveWorkflow();
    collapseCreateWorkflowPanel();
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

  // Cmd/Ctrl+/ to toggle create workflow panel in template mode (only for new workflows)
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

  // Cmd/Ctrl+\ to open import panel (only for new workflows)
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

  return (
    <div className="flex h-full w-full">
      {/* Create Workflow Panel - Always rendered for smooth animations */}
      {isNewWorkflow && (
        <div
          className="flex h-full flex-shrink-0 z-[60]"
          style={{
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
            className="absolute left-0 top-6 z-[61] bg-white border border-gray-200 rounded-r-md p-1 shadow-sm hover:bg-gray-50 transition-colors"
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
                    className={`group flex flex-col items-center text-center bg-white border rounded-xl p-5 transition-all duration-200 cursor-pointer ${
                      isAIAssistantPanelOpen
                        ? 'border-primary-500 ring-2 ring-primary-100 shadow-sm'
                        : 'border-gray-200 hover:border-primary-300 hover:shadow-sm'
                    }`}
                  >
                    <div className="inline-flex items-center justify-center w-12 h-12 rounded-xl bg-primary-50 group-hover:bg-primary-100 mb-4 transition-colors">
                      <span className="hero-sparkles h-6 w-6 text-primary-600" />
                    </div>
                    <h4 className="text-sm font-semibold text-gray-900 mb-1.5 whitespace-nowrap">
                      Generate with AI
                    </h4>
                    <p className="text-xs text-gray-500 leading-relaxed">
                      Build custom workflows with AI
                    </p>
                  </button>

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
