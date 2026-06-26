/**
 * Header sandbox-affordance tests
 *
 * Focused on the gating rules introduced for "Edit in sandbox":
 * - The "Edit in sandbox" button appears only when the workflow is live,
 *   the current project is not itself a sandbox, and the workflow is saved
 *   (not new).
 * - The sandbox badge appears when editing inside a sandbox.
 *
 * The Header pulls in many collaboration hooks and child components; those are
 * mocked to neutral defaults so each test exercises only the gating logic.
 */

import { render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { Header } from '../../../js/collaborative-editor/components/Header';

// ---------------------------------------------------------------------------
// Hook + child-component mocks
// ---------------------------------------------------------------------------

let lifecycleState: 'draft' | 'live' | undefined = 'live';
let isNewWorkflow = false;

vi.mock('../../../js/react/lib/use-url-state', () => ({
  useURLState: () => ({ params: {}, updateSearchParams: vi.fn() }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useHistory', () => ({
  useActiveRun: () => null,
}));

vi.mock('../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: () => ({ provider: null, isSynced: true }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useIsNewWorkflow: () => isNewWorkflow,
  useLimits: () => ({}),
  useProjectRepoConnection: () => null,
  useSessionWorkflow: () => ({ state: lifecycleState }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useUI', () => ({
  useImportPanelState: () => null,
  useIsCreateWorkflowPanelCollapsed: () => true,
  useTemplatePanel: () => ({ selectedTemplate: null }),
  useUICommands: () => ({
    openRunPanel: vi.fn(),
    openGitHubSyncModal: vi.fn(),
  }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useUnsavedChanges', () => ({
  useUnsavedChanges: () => ({ hasChanges: false }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useCanRun: () => ({ canRun: true }),
  useCanSave: () => ({ canSave: true, tooltipMessage: '' }),
  useNodeSelection: () => ({ selectNode: vi.fn() }),
  useWorkflowActions: () => ({
    saveWorkflow: vi.fn(),
    goLive: vi.fn(),
    switchToDraft: vi.fn(),
    listSandboxes: vi.fn(),
    editInSandbox: vi.fn(),
  }),
  useWorkflowReadOnly: () => ({ isReadOnly: false }),
  useWorkflowSettingsErrors: () => ({ hasErrors: false }),
  useWorkflowState: (selector: (state: unknown) => unknown) =>
    selector({ triggers: [], jobs: [] }),
}));

vi.mock('../../../js/collaborative-editor/keyboard', () => ({
  useKeyboardShortcut: vi.fn(),
}));

// Header reads StoreContext via useContext with optional chaining, so leaving
// it unprovided (undefined) is handled gracefully and avoids extra wiring.

// Child components rendered by Header that are irrelevant to the gating logic.
vi.mock(
  '../../../js/collaborative-editor/components/ActiveCollaborators',
  () => ({
    ActiveCollaborators: () => <div data-testid="active-collaborators" />,
  })
);
vi.mock('../../../js/collaborative-editor/components/AIButton', () => ({
  AIButton: () => <div data-testid="ai-button" />,
}));
vi.mock(
  '../../../js/collaborative-editor/components/EmailVerificationBanner',
  () => ({ EmailVerificationBanner: () => <div data-testid="email-banner" /> })
);
vi.mock('../../../js/collaborative-editor/components/GitHubSyncModal', () => ({
  GitHubSyncModal: () => <div data-testid="github-sync-modal" />,
}));
vi.mock('../../../js/collaborative-editor/components/NewRunButton', () => ({
  NewRunButton: () => <div data-testid="new-run-button" />,
}));
vi.mock('../../../js/collaborative-editor/components/ReadOnlyWarning', () => ({
  ReadOnlyWarning: () => <div data-testid="read-only-warning" />,
}));
vi.mock(
  '../../../js/collaborative-editor/components/EditInSandboxPicker',
  () => ({
    EditInSandboxPicker: () => <div data-testid="edit-in-sandbox-picker" />,
  })
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const renderHeader = (
  props: Partial<React.ComponentProps<typeof Header>> = {}
) =>
  render(
    <Header projectId="p1" workflowId="w1" {...props}>
      {[]}
    </Header>
  );

describe('Header - Edit in sandbox button gating', () => {
  beforeEach(() => {
    lifecycleState = 'live';
    isNewWorkflow = false;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  test('shows the button for a live, saved workflow on a non-sandbox project', () => {
    renderHeader({ isSandbox: false });
    expect(screen.getByTestId('edit-in-sandbox-button')).toBeInTheDocument();
  });

  test('hides the button when the workflow is in draft', () => {
    lifecycleState = 'draft';
    renderHeader({ isSandbox: false });
    expect(
      screen.queryByTestId('edit-in-sandbox-button')
    ).not.toBeInTheDocument();
  });

  test('hides the button when already inside a sandbox', () => {
    renderHeader({ isSandbox: true });
    expect(
      screen.queryByTestId('edit-in-sandbox-button')
    ).not.toBeInTheDocument();
  });

  test('hides the button for a new (unsaved) workflow', () => {
    isNewWorkflow = true;
    renderHeader({ isSandbox: false });
    expect(
      screen.queryByTestId('edit-in-sandbox-button')
    ).not.toBeInTheDocument();
  });
});

describe('Header - sandbox badge', () => {
  beforeEach(() => {
    lifecycleState = 'live';
    isNewWorkflow = false;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  test('renders the sandbox badge when editing inside a sandbox', () => {
    renderHeader({ isSandbox: true });
    const badge = screen.getByTestId('workflow-sandbox-badge');
    expect(badge).toBeInTheDocument();
    expect(badge).toHaveTextContent('sandbox');
  });

  test('does not render the sandbox badge outside a sandbox', () => {
    renderHeader({ isSandbox: false });
    expect(
      screen.queryByTestId('workflow-sandbox-badge')
    ).not.toBeInTheDocument();
  });
});
