/**
 * WorkflowEditor - Main workflow editing component
 * Replaces TodoList with workflow-specific functionality
 */

import type React from "react";
import { useSession } from "../contexts/SessionProvider";
import { useWorkflowStore } from "../contexts/WorkflowStoreProvider";
import { CollaborativeMonaco } from "./CollaborativeMonaco";
import { CollaborativeWorkflowDiagram } from "./diagram/CollaborativeWorkflowDiagram";
import { JobsList } from "./JobsList";
import { UserAwareness } from "./UserAwareness";
import { WorkflowHeader } from "./WorkflowHeader";

export const WorkflowEditor: React.FC = () => {
  const workflow = useWorkflowStore((state) => state.workflow);
  const jobs = useWorkflowStore((state) => state.jobs);
  const selectedJobId = useWorkflowStore((state) => state.selectedJobId);
  const getJobBodyYText = useWorkflowStore((state) => state.getJobBodyYText);

  console.log({ workflow, jobs, selectedJobId });

  const { awareness } = useSession();

  const selectedJob = selectedJobId
    ? jobs.find((job) => job.id === selectedJobId)
    : null;

  const selectedJobYText = selectedJobId
    ? getJobBodyYText(selectedJobId)
    : null;

  return (
    <div className="flex flex-col h-full">
      {/* Header Section */}
      <div className="flex-none p-4 border-b border-gray-200">
        {/* Workflow Header */}
        <WorkflowHeader />

        {/* User awareness */}
        <UserAwareness />
      </div>

      {/* Main Content */}
      <div className="flex flex-1 min-h-0 px-4">
        {/* Jobs List Sidebar */}
        <div className="flex-none w-80 border-r border-gray-200 overflow-y-auto">
          <JobsList />

          {/* Workflow statistics */}
          {workflow && (
            <div className="p-4 border-t border-gray-200">
              <div className="flex justify-between text-sm text-gray-500">
                <span>Workflow: {workflow.name}</span>
                <span>{jobs.length} jobs</span>
              </div>
            </div>
          )}
        </div>

        {/* Right Panel - Split vertically */}
        <div className="flex-1 min-w-0 flex flex-col">
          {/* Workflow Diagram */}
          <div className="flex-none h-1/3 border-b border-gray-200">
            <CollaborativeWorkflowDiagram />
          </div>

          {/* Bottom Right - Monaco Editor */}
          <div className="flex-1 min-h-0">
            {selectedJob && selectedJobYText && awareness ? (
              <CollaborativeMonaco
                ytext={selectedJobYText}
                awareness={awareness}
                adaptor="common"
                disabled={false}
                className="h-full w-full"
              />
            ) : (
              <div className="flex items-center justify-center h-full text-gray-500">
                <div className="text-center">
                  <p className="text-lg">Select a job to edit</p>
                  <p className="text-sm">
                    Choose a job from the sidebar to start editing with the
                    collaborative Monaco editor
                  </p>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
