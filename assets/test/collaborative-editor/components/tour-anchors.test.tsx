/**
 * Guided-tour anchor tests
 *
 * The AI assistant's tour runner spotlights DOM nodes by
 * `data-tour-anchor="<element-id>"`. These tests pin the contract on a few
 * representative components: the anchor must land on the interactive element
 * users actually click. The authoritative id list lives with the tour plan;
 * here we only assert the attribute renders.
 */

import { render } from '@testing-library/react';
import { ReactFlowProvider } from '@xyflow/react';
import { describe, expect, test, vi } from 'vitest';

import { AdaptorDisplay } from '../../../js/collaborative-editor/components/AdaptorDisplay';
import { AIButton } from '../../../js/collaborative-editor/components/AIButton';
import { JobInspector } from '../../../js/collaborative-editor/components/inspector/JobInspector';
import { NewRunButton } from '../../../js/collaborative-editor/components/NewRunButton';
import { KeyboardProvider } from '../../../js/collaborative-editor/keyboard';
import type { Workflow } from '../../../js/collaborative-editor/types/workflow';
import JobNode from '../../../js/workflow-diagram/nodes/Job';
import TriggerNode from '../../../js/workflow-diagram/nodes/Trigger';

vi.mock('../../../js/collaborative-editor/hooks/useUI', () => ({
  useUICommands: () => ({ toggleAIAssistantPanel: vi.fn() }),
  useIsAIAssistantPanelOpen: () => false,
}));

vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useCanRun: () => ({ canRun: true, tooltipMessage: 'Run workflow' }),
  useCanSave: () => ({ canSave: true, tooltipMessage: null }),
  useWorkflowActions: () => ({ removeJobAndClearSelection: vi.fn() }),
  useWorkflowReadOnly: () => ({ isReadOnly: false }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useCredentials', () => ({
  useCredentialQueries: () => ({ findCredentialById: () => null }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  usePermissions: () => ({ can_edit_workflow: true }),
}));

vi.mock(
  '../../../js/collaborative-editor/hooks/useJobDeleteValidation',
  () => ({
    useJobDeleteValidation: () => ({ canDelete: true, disableReason: null }),
  })
);

vi.mock('#/react/lib/use-url-state', () => ({
  useURLState: () => ({ params: {}, updateSearchParams: vi.fn() }),
}));

// The form pulls in the whole TanStack Form + Y.Doc stack; the anchor under
// test lives in the inspector footer, so stub it out.
vi.mock(
  '../../../js/collaborative-editor/components/inspector/JobForm',
  () => ({ JobForm: () => null })
);

function anchor(container: HTMLElement, id: string) {
  return container.querySelector(`[data-tour-anchor="${id}"]`);
}

describe('data-tour-anchor', () => {
  test('AIButton carries ai-assistant-toggle on its button', () => {
    const { container } = render(<AIButton />);

    const node = anchor(container, 'ai-assistant-toggle');
    expect(node).toBeInTheDocument();
    expect(node?.tagName).toBe('BUTTON');
  });

  test('NewRunButton renders tourAnchor on the primary button and omits it by default', () => {
    const { container, rerender } = render(
      <NewRunButton onClick={vi.fn()} tourAnchor="run-button" />
    );

    const node = anchor(container, 'run-button');
    expect(node).toBeInTheDocument();
    expect(node?.tagName).toBe('BUTTON');

    // Anchors must be unique per screen, so instances without the prop
    // (inspector, IDE) must not render the attribute at all.
    rerender(<NewRunButton onClick={vi.fn()} />);
    expect(container.querySelector('[data-tour-anchor]')).toBeNull();
  });

  test('AdaptorDisplay anchors the change-adaptor and edit buttons per call site', () => {
    const { container } = render(
      <AdaptorDisplay
        adaptor="@openfn/language-http@latest"
        onEdit={vi.fn()}
        onChangeAdaptor={vi.fn()}
        changeAdaptorTourAnchor="adaptor-picker"
        editTourAnchor="credential-picker"
      />
    );

    const adaptorPicker = anchor(container, 'adaptor-picker');
    expect(adaptorPicker).toBeInTheDocument();
    expect(adaptorPicker).toHaveAttribute('aria-label', 'Change adaptor');

    // The Edit/Connect button opens the Configure connection modal, which is
    // where credentials are picked — hence the id.
    const credentialPicker = anchor(container, 'credential-picker');
    expect(credentialPicker).toBeInTheDocument();
    expect(credentialPicker?.tagName).toBe('BUTTON');
  });

  test('JobNode carries canvas-step on its clickable body; TriggerNode does not', () => {
    const { container } = render(
      <ReactFlowProvider>
        <JobNode
          id="job-1"
          data={{ name: 'My Job', adaptor: '@openfn/language-http@1.0.0' }}
          selected={false}
        />
        <TriggerNode
          id="trigger-1"
          data={{ trigger: { type: 'webhook', enabled: true } } as never}
          selected={false}
        />
      </ReactFlowProvider>
    );

    // Every job node carries the anchor; the tour runner spotlights the
    // first match. Triggers (and placeholders) must not carry it.
    const nodes = container.querySelectorAll('[data-tour-anchor]');
    expect(nodes).toHaveLength(1);
    expect(nodes[0]?.getAttribute('data-tour-anchor')).toBe('canvas-step');
    expect(nodes[0]?.closest('[data-testid="job-node-job-1"]')).not.toBeNull();
  });

  test('JobInspector carries open-editor on the button that opens the IDE', () => {
    const job = {
      id: 'job-1',
      name: 'My Job',
      adaptor: '@openfn/language-http@latest',
      body: '',
      project_credential_id: null,
      keychain_credential_id: null,
    } as Workflow.Job;

    // KeyboardProvider is required by the delete-confirmation AlertDialog.
    const { container } = render(
      <KeyboardProvider>
        <JobInspector job={job} onClose={vi.fn()} onOpenRunPanel={vi.fn()} />
      </KeyboardProvider>
    );

    const node = anchor(container, 'open-editor');
    expect(node).toBeInTheDocument();
    expect(node?.tagName).toBe('BUTTON');
    expect(node).toHaveAttribute('aria-label', 'Code');
  });
});
