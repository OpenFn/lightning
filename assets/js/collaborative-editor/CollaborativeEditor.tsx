import { useMemo } from "react";

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
}: BreadcrumbContentProps) {
  // Get project from store (may be null if not yet loaded)
  const projectFromStore = useProject();

  // Store-first with props-fallback pattern
  // This ensures breadcrumbs work during:
  // 1. Initial server-side render (uses props)
  // 2. Store hydration period (uses props)
  // 3. Full collaborative mode (uses store)
  const projectId = projectFromStore?.id ?? projectIdFallback;
  const projectName = projectFromStore?.name ?? projectNameFallback;

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
        <BreadcrumbText>{workflowName}</BreadcrumbText>
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
  }, [projectId, projectName, workflowName, projectFromStore]);

  return (
    <Header
      {...(projectId !== undefined && { projectId })}
      workflowId={workflowId}
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
            <BreadcrumbContent
              workflowId={workflowId}
              workflowName={workflowName}
              {...(projectId !== undefined && { projectIdFallback: projectId })}
              {...(projectName !== undefined && {
                projectNameFallback: projectName,
              })}
            />
            <div className="flex-1 min-h-0 overflow-hidden">
              <WorkflowEditor />
              <CollaborationWidget />
            </div>
          </StoreProvider>
        </SessionProvider>
      </SocketProvider>
    </div>
  );
};
