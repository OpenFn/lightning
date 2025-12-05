import { useMemo } from 'react';
import YAML from 'yaml';

import {
  useWorkflowState,
  useCanPublishTemplate,
} from '#/collaborative-editor/hooks/useWorkflow';
import { notifications } from '#/collaborative-editor/lib/notifications';
import { useURLState } from '#/react/lib/use-url-state';
import { cn } from '#/utils/cn';
import type { WorkflowState as YAMLWorkflowState } from '#/yaml/types';
import { convertWorkflowStateToSpec } from '#/yaml/util';

export function CodeViewPanel() {
  // Read workflow data from store - LoadingBoundary guarantees non-null
  const workflow = useWorkflowState(state => state.workflow);
  const jobs = useWorkflowState(state => state.jobs);
  const triggers = useWorkflowState(state => state.triggers);
  const edges = useWorkflowState(state => state.edges);
  const positions = useWorkflowState(state => state.positions);

  // Generate YAML from current workflow state
  const yamlCode = useMemo(() => {
    if (!workflow) return '';

    try {
      // Build WorkflowState compatible with YAML utilities
      const workflowState: YAMLWorkflowState = {
        id: workflow.id,
        name: workflow.name,
        jobs: jobs as YAMLWorkflowState['jobs'],
        triggers: triggers as YAMLWorkflowState['triggers'],
        edges: edges as YAMLWorkflowState['edges'],
        positions,
      };

      // Convert to spec without IDs (cleaner for export)
      const spec = convertWorkflowStateToSpec(workflowState, false);
      return YAML.stringify(spec);
    } catch (error) {
      console.error('Failed to generate YAML:', error);
      return '# Error generating YAML\n# Please check console for details';
    }
  }, [workflow, jobs, triggers, edges, positions]);

  // Generate sanitized filename from workflow name
  const fileName = useMemo(() => {
    if (!workflow) return 'workflow.yaml';
    // Remove special characters, replace spaces with hyphens
    const sanitized = workflow.name
      .replace(/[^a-zA-Z0-9-_\s]/g, '')
      .replace(/\s+/g, '-');
    return `${sanitized}.yaml`;
  }, [workflow]);

  // Download YAML as file
  const handleDownload = () => {
    const blob = new Blob([yamlCode], { type: 'text/yaml' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  // Copy YAML to clipboard with notification feedback
  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(yamlCode);
      notifications.info({
        title: 'Code copied',
        description: 'Workflow YAML copied to clipboard',
      });
    } catch (error) {
      console.error('Failed to copy:', error);
      notifications.alert({
        title: 'Failed to copy',
        description: 'Could not copy to clipboard. Please try again.',
      });
    }
  };

  // Template publishing state and handlers
  const { canPublish, buttonDisabled, tooltipMessage, buttonText } =
    useCanPublishTemplate();
  const { updateSearchParams } = useURLState();

  const handlePublishTemplate = () => {
    updateSearchParams({ panel: 'publish-template' });
  };

  if (!workflow) {
    return <div className="px-4 py-5 text-gray-500">Loading...</div>;
  }

  return (
    <>
      {/* Code Display */}
      <div className="px-4 py-5 sm:p-6">
        <textarea
          id="workflow-code-viewer"
          className="w-full font-mono text-sm
            bg-slate-700 text-slate-200 rounded-md shadow-xs p-4
            border border-slate-300 resize-none
            text-nowrap overflow-x-auto overflow-y-auto
            focus:outline focus:outline-2 focus:outline-offset-1
            focus:ring-0 focus:border-slate-400 focus:outline-primary-600"
          value={yamlCode}
          readOnly
          rows={18}
          spellCheck={false}
          aria-label="Workflow YAML code"
        />
      </div>

      {/* Actions Footer */}
      <div className="shrink-0 border-t border-gray-200 p-3 -mt-px">
        <div className="flex justify-end gap-2">
          <button
            id="download-workflow-code-btn"
            type="button"
            onClick={handleDownload}
            className="rounded-md px-3 py-2 text-sm font-semibold
              bg-white hover:bg-gray-50 text-gray-900
              ring-1 ring-inset ring-gray-300 shadow-xs"
          >
            Download
          </button>
          <button
            id="copy-workflow-code-btn"
            type="button"
            onClick={() => void handleCopy()}
            className="rounded-md px-3 py-2 text-sm font-semibold
              bg-white hover:bg-gray-50 text-gray-900
              ring-1 ring-inset ring-gray-300 shadow-xs min-w-[6rem]"
          >
            Copy Code
          </button>
          {canPublish && (
            <button
              id="publish-template-btn"
              type="button"
              onClick={handlePublishTemplate}
              disabled={buttonDisabled}
              {...(tooltipMessage && { title: tooltipMessage })}
              className={cn(
                'rounded-md px-3 py-2 text-sm font-semibold shadow-xs min-w-[8rem]',
                buttonDisabled
                  ? 'bg-primary-300 text-white cursor-not-allowed'
                  : 'bg-primary-600 text-white hover:bg-primary-700 cursor-pointer'
              )}
            >
              {buttonText}
            </button>
          )}
        </div>
      </div>
    </>
  );
}
