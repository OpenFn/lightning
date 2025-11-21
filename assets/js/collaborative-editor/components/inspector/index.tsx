/**
 * Inspector - Side panel component for displaying node details
 * Shows details for jobs, triggers, and edges when selected
 */

import { useURLState } from '../../../react/lib/use-url-state';
import { useKeyboardShortcut } from '../../keyboard';
import type { Workflow } from '../../types/workflow';

import { CodeViewPanel } from './CodeViewPanel';
import { EdgeInspector } from './EdgeInspector';
import { InspectorLayout } from './InspectorLayout';
import { JobInspector } from './JobInspector';
import { TriggerInspector } from './TriggerInspector';
import { WorkflowSettings } from './WorkflowSettings';
import { TemplatePublishPanel } from './TemplatePublishPanel';
import { useWorkflowTemplate } from '../../hooks/useSessionContext';

export { InspectorLayout } from './InspectorLayout';

// import _logger from "#/utils/logger";
// const logger = _logger.ns("Inspector").seal();

interface InspectorProps {
  currentNode: {
    node: Workflow.Node | null;
    type: Workflow.NodeType | null;
    id: string | null;
  };
  onClose: () => void;
  onOpenRunPanel: (context: { jobId?: string; triggerId?: string }) => void;
}

export function Inspector({
  currentNode,
  onClose,
  onOpenRunPanel,
}: InspectorProps) {
  const { searchParams, updateSearchParams } = useURLState();
  const workflowTemplate = useWorkflowTemplate();

  const hasSelectedNode = currentNode.node && currentNode.type;

  // Settings and code panels take precedence, then node inspector
  const mode =
    searchParams.get('panel') === 'settings'
      ? 'settings'
      : searchParams.get('panel') === 'code'
        ? 'code'
        : searchParams.get('panel') === 'publish-template'
          ? 'publish-template'
          : hasSelectedNode
            ? 'node'
            : null;

  const handleClose = () => {
    if (mode === 'code') {
      // When closing code view, go back to settings
      updateSearchParams({ panel: 'settings' });
    } else if (mode === 'publish-template') {
      updateSearchParams({ panel: 'code' });
    } else if (mode === 'settings') {
      updateSearchParams({ panel: null });
    } else {
      onClose(); // Clears node selection
    }
  };

  useKeyboardShortcut(
    'Escape',
    () => {
      handleClose();
    },
    10 // PANEL priority
  );

  // Don't render if no mode selected
  if (!mode) return null;

  // Settings mode
  if (mode === 'settings') {
    return (
      <InspectorLayout
        title="Workflow settings"
        onClose={handleClose}
        fullHeight
      >
        <WorkflowSettings />
      </InspectorLayout>
    );
  }

  // Code view mode
  if (mode === 'code') {
    return (
      <InspectorLayout
        title="Workflow as Code"
        onClose={handleClose}
        fullHeight
      >
        <CodeViewPanel />
      </InspectorLayout>
    );
  }

  // Publish template mode
  if (mode === 'publish-template') {
    const title = workflowTemplate
      ? 'Update Template'
      : 'Publish Workflow as Template';

    return (
      <InspectorLayout title={title} onClose={handleClose}>
        <TemplatePublishPanel />
      </InspectorLayout>
    );
  }

  // Node inspector mode
  if (currentNode.type === 'job') {
    return (
      <JobInspector
        key={`job-${currentNode.id}`}
        job={currentNode.node as Workflow.Job}
        onClose={handleClose}
        onOpenRunPanel={onOpenRunPanel}
      />
    );
  }

  if (currentNode.type === 'trigger') {
    return (
      <TriggerInspector
        key={`trigger-${currentNode.id}`}
        trigger={currentNode.node as Workflow.Trigger}
        onClose={handleClose}
        onOpenRunPanel={onOpenRunPanel}
      />
    );
  }

  if (currentNode.type === 'edge') {
    return (
      <EdgeInspector
        key={`edge-${currentNode.id}`}
        edge={currentNode.node as Workflow.Edge}
        onClose={handleClose}
      />
    );
  }

  return null;
}

// Helper function to open workflow settings from external components
export const openWorkflowSettings = () => {
  const params = new URLSearchParams(window.location.search);
  params.set('panel', 'settings');
  const newURL = `${window.location.pathname}?${params.toString()}`;
  history.pushState({}, '', newURL);
};
