import { useCallback, useEffect, useMemo, useState } from "react";
import { HotkeysProvider, useHotkeysContext } from "react-hotkeys-hook";

import { SocketProvider } from "../react/contexts/SocketProvider";
import type { WithActionProps } from "../react/lib/with-props";

import { BreadcrumbLink, BreadcrumbText } from "./components/Breadcrumbs";
import { CollaborationWidget } from "./components/CollaborationWidget";
import { Header } from "./components/Header";
import { Toaster } from "./components/ui/Toaster";
import { WorkflowEditor } from "./components/WorkflowEditor";
import { SessionProvider } from "./contexts/SessionProvider";
import { StoreProvider } from "./contexts/StoreProvider";
import { useProject } from "./hooks/useSessionContext";
import { useNodeSelection, useWorkflowState } from "./hooks/useWorkflow";

export interface CollaborativeEditorDataProps {
  "data-workflow-id": string;
  "data-workflow-name": string;
  "data-project-id": string;
  "data-project-name"?: string;
  "data-is-new-workflow"?: string;
}

/**
 * BreadcrumbContent Component
 *
 * Internal component that renders breadcrumbs with store-first, props-fallback pattern.
 * This component must be inside StoreProvider to access sessionContextStore.
 *
 * Migration Strategy:
 * - Tries to get project data from sessionContextStore first
 * - Falls back to props if store data not yet available
 * - This ensures breadcrumbs work during migration and server-side rendering
 * - Eventually props can be removed when all project data flows through store
 */
interface BreadcrumbContentProps {
  workflowId: string;
  workflowName: string;
  projectIdFallback?: string;
  projectNameFallback?: string;
}

function BreadcrumbContent({
  workflowId,
  workflowName,
  projectIdFallback,
  projectNameFallback,
  onOpenRunPanel,
}: BreadcrumbContentProps & {
  onOpenRunPanel?: (context: { jobId?: string; triggerId?: string }) => void;
}) {
  // Get project from store (may be null if not yet loaded)
  const projectFromStore = useProject();

  // Get workflow from store to read the current name
  const workflowFromStore = useWorkflowState(state => state.workflow);

  // Store-first with props-fallback pattern
  // This ensures breadcrumbs work during:
  // 1. Initial server-side render (uses props)
  // 2. Store hydration period (uses props)
  // 3. Full collaborative mode (uses store)
  const projectId = projectFromStore?.id ?? projectIdFallback;
  const projectName = projectFromStore?.name ?? projectNameFallback;
  const currentWorkflowName = workflowFromStore?.name ?? workflowName;

  const breadcrumbElements = useMemo(() => {
    return [
      <BreadcrumbLink href="/" icon="hero-home-mini" key="home">
        Home
      </BreadcrumbLink>,
      <BreadcrumbLink href="/projects" key="projects">
        Projects
      </BreadcrumbLink>,
      <BreadcrumbLink href={`/projects/${projectId}/w`} key="project">
        {projectName}
      </BreadcrumbLink>,
      <BreadcrumbLink href={`/projects/${projectId}/w`} key="workflows">
        Workflows
      </BreadcrumbLink>,
      <div key="workflow" className="flex items-center gap-2">
        <BreadcrumbText>{currentWorkflowName}</BreadcrumbText>
        <div
          id="canvas-workflow-version-container"
          className="flex items-middle text-sm font-normal"
        >
          <span
            id="canvas-workflow-version"
            className="inline-flex items-center rounded-md px-1.5 py-0.5 text-xs font-medium bg-blue-100 text-blue-800"
            title="This is the latest version of this workflow"
          >
            latest
          </span>
        </div>
      </div>,
    ];
  }, [projectId, projectName, currentWorkflowName]);

  return (
    <Header
      {...(projectId !== undefined && { projectId })}
      workflowId={workflowId}
      onOpenRunPanel={onOpenRunPanel}
    >
      {breadcrumbElements}
    </Header>
  );
}

export const CollaborativeEditor: WithActionProps<
  CollaborativeEditorDataProps
> = props => {
  // Extract data from props (ReactComponent hook passes data attributes as props)
  const workflowId = props["data-workflow-id"];
  const workflowName = props["data-workflow-name"];
  // Migration: Props are now fallbacks, sessionContextStore is primary source
  const projectId = props["data-project-id"];
  const projectName = props["data-project-name"];
  const isNewWorkflow = props["data-is-new-workflow"] === "true";

  return (
    <HotkeysProvider initiallyActiveScopes={["global"]}>
      <div
        className="collaborative-editor h-full flex flex-col"
        data-testid="collaborative-editor"
      >
        <SocketProvider>
          <SessionProvider
            workflowId={workflowId}
            projectId={projectId}
            isNewWorkflow={isNewWorkflow}
          >
            <StoreProvider>
              <Toaster />
              <InnerEditor
                workflowId={workflowId}
                workflowName={workflowName}
                projectId={projectId}
                projectName={projectName}
              />
            </StoreProvider>
          </SessionProvider>
        </SocketProvider>
      </div>
    </HotkeysProvider>
  );
};

/**
 * Inner editor component that manages run panel state
 * Needs to be inside StoreProvider to share state between Header and WorkflowEditor
 */
function InnerEditor({
  workflowId,
  workflowName,
  projectId,
  projectName,
}: {
  workflowId: string;
  workflowName: string;
  projectId?: string;
  projectName?: string;
}) {
  // Run panel state - lifted to this level so both Header and WorkflowEditor can access
  const [runPanelContext, setRunPanelContext] = useState<{
    jobId?: string;
    triggerId?: string;
  } | null>(null);

  // Get current node selection from URL
  const { currentNode } = useNodeSelection();

  // Use HotkeysContext to manage scope precedence for run panel
  const { enableScope, disableScope } = useHotkeysContext();

  // Manage "panel" scope based on whether run panel is open
  // When run panel opens, disable "panel" scope so InspectorLayout's Escape doesn't fire
  // When run panel closes, re-enable "panel" scope so InspectorLayout's Escape works again
  useEffect(() => {
    if (runPanelContext) {
      // Run panel is open - disable panel scope
      disableScope("panel");
    } else {
      // Run panel is closed - enable panel scope
      enableScope("panel");
    }
  }, [runPanelContext, enableScope, disableScope]);

  // Update run panel context when selected node changes (if panel is open)
  useEffect(() => {
    if (runPanelContext) {
      // Panel is open, update context based on selected node
      if (currentNode.type === "job" && currentNode.node) {
        setRunPanelContext({ jobId: currentNode.node.id });
      } else if (currentNode.type === "trigger" && currentNode.node) {
        setRunPanelContext({ triggerId: currentNode.node.id });
      } else if (currentNode.type === "edge" || !currentNode.node) {
        // Close panel if edge selected or nothing selected (clicked canvas)
        setRunPanelContext(null);
      }
    }
  }, [currentNode.type, currentNode.node, runPanelContext]);

  const openRunPanel = useCallback(
    (context: { jobId?: string; triggerId?: string }) => {
      setRunPanelContext(context);
    },
    []
  );

  const closeRunPanel = useCallback(() => {
    setRunPanelContext(null);
  }, []);

  return (
    <>
      <BreadcrumbContent
        workflowId={workflowId}
        workflowName={workflowName}
        {...(projectId !== undefined && {
          projectIdFallback: projectId,
        })}
        {...(projectName !== undefined && {
          projectNameFallback: projectName,
        })}
        onOpenRunPanel={openRunPanel}
      />
      <div className="flex-1 min-h-0 overflow-hidden">
        <WorkflowEditor
          runPanelContext={runPanelContext}
          onOpenRunPanel={openRunPanel}
          onCloseRunPanel={closeRunPanel}
        />
        <CollaborationWidget />
      </div>
    </>
  );
}
