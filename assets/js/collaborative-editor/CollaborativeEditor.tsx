import { useMemo } from "react";
import { SocketProvider } from "../react/contexts/SocketProvider";
import type { WithActionProps } from "../react/lib/with-props";
import {
  BreadcrumbLink,
  BreadcrumbText,
} from "./components/Breadcrumbs";
import { CollaborationWidget } from "./components/CollaborationWidget";
import { WorkflowEditor } from "./components/WorkflowEditor";
import { SessionProvider } from "./contexts/SessionProvider";
import { WorkflowStoreProvider } from "./contexts/WorkflowStoreProvider";
import type { CollaborativeEditorDataProps } from "./types/workflow";
import { Header } from "./components/Header";

export const CollaborativeEditor: WithActionProps<
  CollaborativeEditorDataProps
> = (props) => {
  // Extract data from props (ReactComponent hook passes data attributes as props)
  const workflowId = props["data-workflow-id"];
  const workflowName = props["data-workflow-name"];
  const userId = props["data-user-id"];
  const userName = props["data-user-name"];
  const projectId = props["data-project-id"];
  const projectName = props["data-project-name"];

  const breadcrumbElements = useMemo(() => {
    return [
      <BreadcrumbLink href="/" icon="hero-home-mini" key="home">
        Home
      </BreadcrumbLink>,
      <BreadcrumbLink href="/projects" key="projects">
        Projects
      </BreadcrumbLink>,
      <BreadcrumbLink href={`/projects/${projectId}`} key="project">
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
  }, [projectId, projectName, workflowName]);

  return (
    <div className="collaborative-editor h-full flex flex-col">
      <Header>{breadcrumbElements}</Header>
      <SocketProvider>
        <SessionProvider
          workflowId={workflowId}
          userId={userId}
          userName={userName}
        >
          {/* New WorkflowStoreProvider for workflow editing */}
          <WorkflowStoreProvider>
            <div className="flex-1 min-h-0 overflow-hidden">
              <WorkflowEditor />
              <CollaborationWidget />
            </div>
          </WorkflowStoreProvider>
        </SessionProvider>
      </SocketProvider>
    </div>
  );
};
