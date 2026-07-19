// Header sandbox-affordance tests: gating, lifecycle badge, and the go-live / switch-to-draft / edit-in-sandbox actions.

import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { BreadcrumbText } from '../../../js/collaborative-editor/components/Breadcrumbs';
import { Header } from '../../../js/collaborative-editor/components/Header';

// ---------------------------------------------------------------------------
// Hook + child-component mocks
// ---------------------------------------------------------------------------

let lifecycleState: 'draft' | 'live' | undefined = 'live';
let isNewWorkflow = false;
let canProvisionSandbox = true;

const goLive = vi.fn<() => Promise<unknown>>();
const switchToDraft = vi.fn<() => Promise<unknown>>();

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
  usePermissions: () => ({ can_provision_sandbox: canProvisionSandbox }),
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
    goLive,
    switchToDraft,
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
    EditInSandboxPicker: ({ isOpen }: { isOpen: boolean }) =>
      isOpen ? <div data-testid="edit-in-sandbox-picker" /> : null,
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
    canProvisionSandbox = true;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  test('shows an enabled button when the user can provision a sandbox', () => {
    renderHeader({ isSandbox: false });
    const button = screen.getByTestId('edit-in-sandbox-button');
    expect(button).toBeEnabled();
    // No tooltip wrapper: the Tooltip renders bare children when content is null,
    // so the Radix trigger attribute is absent when provisioning is allowed.
    expect(button).not.toHaveAttribute('data-state');
  });

  test('renders the button disabled and tooltip-wrapped when provisioning is not allowed', () => {
    canProvisionSandbox = false;
    renderHeader({ isSandbox: false });

    const button = screen.getByTestId('edit-in-sandbox-button');
    expect(button).toBeDisabled();
    // The disabled button is wrapped in the shared Tooltip, so Radix marks it as
    // a trigger with a data-state attribute.
    expect(button).toHaveAttribute('data-state');
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

describe('Header - lifecycle actions', () => {
  beforeEach(() => {
    lifecycleState = 'live';
    isNewWorkflow = false;
    canProvisionSandbox = true;
    goLive.mockReset();
    switchToDraft.mockReset();
    goLive.mockResolvedValue(undefined);
    switchToDraft.mockResolvedValue(undefined);
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  test('renders the lifecycle badge for the current state', () => {
    renderHeader();
    expect(screen.getByTestId('workflow-lifecycle-badge')).toHaveTextContent(
      'Live'
    );

    lifecycleState = 'draft';
    renderHeader();
    const badges = screen.getAllByTestId('workflow-lifecycle-badge');
    expect(badges.at(-1)).toHaveTextContent('Draft');
  });

  test('clicking go live triggers the go-live action', async () => {
    const user = userEvent.setup();
    lifecycleState = 'draft';
    renderHeader();

    await user.click(screen.getByTestId('go-live-button'));

    await waitFor(() => {
      expect(goLive).toHaveBeenCalledTimes(1);
    });
  });

  test('switch to draft requires confirmation before running', async () => {
    const user = userEvent.setup();
    renderHeader();

    await user.click(screen.getByTestId('switch-to-draft-button'));

    // The confirmation dialog opens; the action only fires once confirmed.
    const dialog = screen.getByRole('dialog');
    expect(within(dialog).getByText('Switch to draft?')).toBeInTheDocument();
    expect(switchToDraft).not.toHaveBeenCalled();

    await user.click(
      within(dialog).getByRole('button', { name: 'Switch to draft' })
    );

    await waitFor(() => {
      expect(switchToDraft).toHaveBeenCalledTimes(1);
    });
  });

  test('clicking edit in sandbox opens the picker', async () => {
    const user = userEvent.setup();
    renderHeader({ isSandbox: false });

    expect(
      screen.queryByTestId('edit-in-sandbox-picker')
    ).not.toBeInTheDocument();

    await user.click(screen.getByTestId('edit-in-sandbox-button'));

    expect(screen.getByTestId('edit-in-sandbox-picker')).toBeInTheDocument();
  });

  test('inside a sandbox, shows a disabled Promote button and no lifecycle transitions', () => {
    renderHeader({ isSandbox: true });

    const promote = screen.getByTestId('promote-sandbox-button');
    expect(promote).toBeDisabled();
    expect(promote).toHaveTextContent('Promote');
    // Wrapped in the shared Tooltip ("Coming soon"), so Radix marks it a trigger.
    expect(promote).toHaveAttribute('data-state');

    // The main-project lifecycle actions are not offered inside a sandbox.
    expect(screen.queryByTestId('go-live-button')).not.toBeInTheDocument();
    expect(
      screen.queryByTestId('switch-to-draft-button')
    ).not.toBeInTheDocument();
    expect(
      screen.queryByTestId('workflow-lifecycle-badge')
    ).not.toBeInTheDocument();
  });
});

describe('Header - long workflow name', () => {
  beforeEach(() => {
    lifecycleState = 'live';
    isNewWorkflow = false;
    canProvisionSandbox = true;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  test('truncates a long workflow name so the save action stays visible', () => {
    const longName = 'Really-long-workflow-name-'.repeat(6);

    render(
      <Header projectId="p1" workflowId="w1">
        {[<BreadcrumbText key="wf">{longName}</BreadcrumbText>]}
      </Header>
    );

    // The name renders with an ellipsis cap rather than pushing the layout.
    const nameEl = screen.getByText(longName);
    expect(nameEl).toHaveClass('truncate');
    expect(nameEl.className).toContain('max-w-');

    // The primary action remains rendered alongside the long name.
    expect(screen.getByTestId('save-workflow-button')).toBeInTheDocument();
  });
});
