/**
 * Restore wiring tests
 *
 * The dialog's whole job is to say what a rollback costs. These drive the real
 * breadcrumbs so that the answer the user sees is the answer for the version
 * they are actually restoring, which is not free: a check for a version they
 * have since cancelled can land after a later one.
 */

import { act, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { BreadcrumbContent } from '../../../js/collaborative-editor/CollaborativeEditor';
import { KeyboardProvider } from '../../../js/collaborative-editor/keyboard';
import {
  createMockURLState,
  getURLStateMockValue,
} from '../__helpers__/urlStateMocks';

const urlState = createMockURLState();

type CheckReply = {
  losing_triggers: {
    id: string;
    type: string;
    custom_path: string | null;
    enabled: boolean;
  }[];
  returning_triggers: {
    id: string;
    type: string;
    custom_path: string | null;
  }[];
  version_number: number;
};

const checkRestore = vi.fn<(v: number) => Promise<CheckReply>>();
const restoreVersion = vi.fn<() => Promise<{ lock_version: number }>>();

vi.mock('#/react/lib/use-url-state', () => ({
  useURLState: () => getURLStateMockValue(urlState),
}));

vi.mock('@monaco-editor/react', () => ({
  default: () => <div data-testid="monaco-editor" />,
}));

vi.mock(
  '../../../js/collaborative-editor/components/CollaborativeMonaco',
  () => ({
    CollaborativeMonaco: () => <div data-testid="collaborative-monaco" />,
  })
);

vi.mock('../../../js/collaborative-editor/components/WorkflowEditor', () => ({
  WorkflowEditor: () => <div data-testid="workflow-editor" />,
}));

vi.mock('../../../js/collaborative-editor/components/Header', () => ({
  Header: ({ children }: { children: React.ReactNode }) => (
    <div data-testid="header">{children}</div>
  ),
}));

// Real triggers for the real handler, so the wiring between them is tested.
vi.mock('../../../js/collaborative-editor/components/VersionDropdown', () => ({
  VersionDropdown: ({
    onVersionRestore,
  }: {
    onVersionRestore?: (version: number) => void;
  }) => (
    <>
      <button data-testid="ask-restore-3" onClick={() => onVersionRestore?.(3)}>
        Restore 3
      </button>
      <button data-testid="ask-restore-5" onClick={() => onVersionRestore?.(5)}>
        Restore 5
      </button>
    </>
  ),
}));

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useProject: () => ({ id: 'project-1', name: 'Test Project' }),
  useLatestSnapshotLockVersion: () => 1,
  useIsNewWorkflow: () => false,
  usePermissions: () => ({ can_edit_workflow: true }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowActions: () => ({ restoreVersion, checkRestore }),
  useWorkflowState: (selector: (state: unknown) => unknown) => {
    const state = { workflow: { id: 'workflow-1', lock_version: 1 } };
    return typeof selector === 'function' ? selector(state) : state;
  },
}));

vi.mock('../../../js/collaborative-editor/hooks/useUI', () => ({
  useIsRunPanelOpen: () => false,
  useUICommands: () => ({ closeRunPanel: vi.fn() }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useHistory', () => ({
  useHistoryCommands: () => ({ closeRunViewer: vi.fn() }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useVersionSelect', () => ({
  useVersionSelect: () => ({
    handleVersionSelect: vi.fn(),
    prompt: {
      isAsking: false,
      cancel: vi.fn(),
      runPending: vi.fn(),
      saveAndRunPending: vi.fn(),
    },
  }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useUnloadWarning', () => ({
  useUnloadWarning: () => {},
}));

const webhook = {
  id: 'trigger-1',
  type: 'webhook',
  custom_path: 'payments',
  enabled: true,
};

function renderBreadcrumbs() {
  return render(
    <KeyboardProvider>
      <BreadcrumbContent
        workflowId="workflow-1"
        workflowName="Test Workflow"
        aiAssistantEnabled={false}
      />
    </KeyboardProvider>
  );
}

describe('restore, wired up', () => {
  beforeEach(() => {
    urlState.reset();
    checkRestore.mockReset();
    restoreVersion.mockReset();
    restoreVersion.mockResolvedValue({ lock_version: 2 });
  });

  test('shows the cost of the version being restored', async () => {
    checkRestore.mockResolvedValue({
      losing_triggers: [webhook],
      returning_triggers: [],
      version_number: 3,
    });
    const user = userEvent.setup();
    renderBreadcrumbs();

    await user.click(screen.getByTestId('ask-restore-3'));

    expect(
      await screen.findByTestId('restore-losing-triggers')
    ).toHaveTextContent('the webhook at /payments');
  });

  test('a late answer for an abandoned version does not silence a real warning', async () => {
    // v3's check is slow and empty; v5's is immediate and has a warning. The
    // user cancels v3 and asks for v5, so the late v3 answer must be ignored.
    let releaseV3: ((reply: CheckReply) => void) | null = null;

    checkRestore.mockImplementation((version: number) => {
      if (version === 3) {
        return new Promise<CheckReply>(resolve => {
          releaseV3 = resolve;
        });
      }

      return Promise.resolve({
        losing_triggers: [webhook],
        returning_triggers: [],
        version_number: 5,
      });
    });

    const user = userEvent.setup();
    renderBreadcrumbs();

    await user.click(screen.getByTestId('ask-restore-3'));
    await user.click(screen.getByRole('button', { name: 'Cancel' }));
    await user.click(screen.getByTestId('ask-restore-5'));

    expect(
      await screen.findByTestId('restore-losing-triggers')
    ).toBeInTheDocument();

    // Let the late answer land and flush, or the assertion below passes on the
    // state as it was before it arrived.
    await act(async () => {
      releaseV3?.({
        losing_triggers: [],
        returning_triggers: [],
        version_number: 3,
      });

      await Promise.resolve();
    });

    // Still warning about v5's trigger, not blanked by v3's empty answer.
    expect(screen.getByTestId('restore-losing-triggers')).toHaveTextContent(
      'the webhook at /payments'
    );
  });

  test('a failed check does not block the rollback', async () => {
    checkRestore.mockRejectedValue(new Error('no answer'));
    const user = userEvent.setup();
    renderBreadcrumbs();

    await user.click(screen.getByTestId('ask-restore-3'));

    await waitFor(() => {
      expect(
        screen.getByRole('button', { name: /^Restore v3$/ })
      ).toBeEnabled();
    });
  });
});
