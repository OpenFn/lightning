// Header sandbox-affordance tests: gating, lifecycle badge, and the go-live / switch-to-draft / edit-in-sandbox actions.

import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { BreadcrumbText } from '../../../js/collaborative-editor/components/Breadcrumbs';
import { Header } from '../../../js/collaborative-editor/components/Header';
import { ChannelRequestError } from '../../../js/collaborative-editor/lib/errors';

// ---------------------------------------------------------------------------
// Hook + child-component mocks
// ---------------------------------------------------------------------------

let lifecycleState: 'draft' | 'live' | undefined = 'live';
let isNewWorkflow = false;
let canProvisionSandbox = true;
let canArchiveSandbox = true;
let readOnly: {
  isReadOnly: boolean;
  reason:
    | 'deleted'
    | 'live'
    | 'no_permission'
    | 'pinned_version'
    | 'unsaved_new'
    | null;
} = { isReadOnly: false, reason: null };

const goLive = vi.fn<() => Promise<unknown>>();
const switchToDraft = vi.fn<() => Promise<unknown>>();
const saveWorkflow =
  vi.fn<(options?: { silent?: boolean }) => Promise<unknown>>();
const promote = vi.fn<
  () => Promise<{
    parent_project_id: string;
    workflow_id: string | null;
  }>
>();
const archiveSandbox = vi.fn<() => Promise<{ parent_project_id: string }>>();

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
  usePermissions: () => ({
    can_provision_sandbox: canProvisionSandbox,
    can_archive_sandbox: canArchiveSandbox,
  }),
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
    saveWorkflow,
    goLive,
    switchToDraft,
    listSandboxes: vi.fn(),
    editInSandbox: vi.fn(),
    promote,
    archiveSandbox,
  }),
  useWorkflowReadOnly: () => readOnly,
  useWorkflowSettingsErrors: () => ({ hasErrors: false }),
  useWorkflowState: (selector: (state: unknown) => unknown) =>
    selector({ triggers: [], jobs: [] }),
}));

vi.mock('../../../js/collaborative-editor/keyboard', () => ({
  useKeyboardShortcut: vi.fn(),
}));

const notifySuccess = vi.fn<(opts: unknown) => void>();
const notifyInfo = vi.fn<(opts: unknown) => void>();
const notifyAlert = vi.fn<(opts: unknown) => void>();
vi.mock('../../../js/collaborative-editor/lib/notifications', () => ({
  notifications: {
    success: (opts: unknown) => {
      notifySuccess(opts);
    },
    info: (opts: unknown) => {
      notifyInfo(opts);
    },
    alert: (opts: unknown) => {
      notifyAlert(opts);
    },
  },
}));

// Stub the hard-navigation Header performs after a successful promote.
function stubNavigation() {
  const originalLocation = window.location;
  const hrefSetter = vi.fn();
  Object.defineProperty(window, 'location', {
    configurable: true,
    value: {
      ...originalLocation,
      set href(value: string) {
        hrefSetter(value);
      },
    },
  });
  return {
    hrefSetter,
    restore: () => {
      Object.defineProperty(window, 'location', {
        configurable: true,
        value: originalLocation,
      });
    },
  };
}

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
    canArchiveSandbox = true;
    readOnly = { isReadOnly: false, reason: null };
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
    canArchiveSandbox = true;
    readOnly = { isReadOnly: false, reason: null };
    goLive.mockReset();
    switchToDraft.mockReset();
    saveWorkflow.mockReset();
    promote.mockReset();
    archiveSandbox.mockReset();
    notifySuccess.mockReset();
    notifyInfo.mockReset();
    notifyAlert.mockReset();
    goLive.mockResolvedValue(undefined);
    switchToDraft.mockResolvedValue(undefined);
    saveWorkflow.mockResolvedValue(undefined);
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

  test('suppresses the redundant Read-only badge on a live workflow but keeps it on a draft', () => {
    // Live already implies read-only, so the "Read-only" pill is hidden.
    renderHeader();
    expect(screen.queryByTestId('read-only-warning')).not.toBeInTheDocument();

    // A draft has no Live badge, so the "Read-only" pill is still rendered.
    lifecycleState = 'draft';
    renderHeader();
    const warnings = screen.getAllByTestId('read-only-warning');
    expect(warnings.at(-1)).toBeInTheDocument();
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
    expect(
      within(dialog).getByText(/takes the workflow out of production/i)
    ).toBeInTheDocument();
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

  test('inside a sandbox, shows an enabled Promote button and no lifecycle transitions', () => {
    renderHeader({ isSandbox: true });

    const promoteButton = screen.getByTestId('promote-sandbox-button');
    expect(promoteButton).toBeEnabled();
    expect(promoteButton).toHaveTextContent('Promote');
    // No longer wrapped in the "Coming soon" Tooltip, so no Radix trigger marker.
    expect(promoteButton).not.toHaveAttribute('data-state');

    // The main-project lifecycle actions are not offered inside a sandbox.
    expect(screen.queryByTestId('go-live-button')).not.toBeInTheDocument();
    expect(
      screen.queryByTestId('switch-to-draft-button')
    ).not.toBeInTheDocument();
    expect(
      screen.queryByTestId('workflow-lifecycle-badge')
    ).not.toBeInTheDocument();
  });

  // Walk the dialog through phase one: open it and confirm the save-and-merge.
  const confirmPromote = async (user: ReturnType<typeof userEvent.setup>) => {
    await user.click(screen.getByTestId('promote-sandbox-button'));
    await user.click(
      within(screen.getByRole('dialog')).getByRole('button', {
        name: 'Save and promote',
      })
    );
  };

  test('clicking Promote opens the save-and-promote confirm dialog without acting yet', async () => {
    const user = userEvent.setup();
    renderHeader({ isSandbox: true });

    await user.click(screen.getByTestId('promote-sandbox-button'));

    const dialog = screen.getByRole('dialog');
    expect(
      within(dialog).getByText('Save and promote to parent project')
    ).toBeInTheDocument();
    expect(
      within(dialog).getByText(/current changes in this sandbox are saved/i)
    ).toBeInTheDocument();
    // Neither the save nor the promote fires until the user confirms.
    expect(saveWorkflow).not.toHaveBeenCalled();
    expect(promote).not.toHaveBeenCalled();
  });

  test('confirming saves before merging, then shows the success step without navigating', async () => {
    const user = userEvent.setup();
    promote.mockResolvedValue({
      parent_project_id: 'parent-1',
      workflow_id: 'wf-parent',
    });

    const nav = stubNavigation();
    try {
      renderHeader({ isSandbox: true });

      await confirmPromote(user);

      await waitFor(() => {
        expect(promote).toHaveBeenCalledTimes(1);
      });
      // The current editor state is saved (silently) before the merge, and the
      // save happens first.
      expect(saveWorkflow).toHaveBeenCalledWith({ silent: true });
      expect(saveWorkflow.mock.invocationCallOrder[0]).toBeLessThan(
        promote.mock.invocationCallOrder[0]
      );

      // Promote merges only: the dialog advances to its success step rather than
      // hard-navigating away.
      const dialog = screen.getByRole('dialog');
      await waitFor(() => {
        expect(
          within(dialog).getByText('Changes promoted')
        ).toBeInTheDocument();
      });
      expect(nav.hrefSetter).not.toHaveBeenCalled();
      // No inline toast yet; the user chooses keep-or-archive first.
      expect(notifySuccess).not.toHaveBeenCalled();
    } finally {
      nav.restore();
    }
  });

  test('keeping the sandbox stays put with a toast and never archives', async () => {
    const user = userEvent.setup();
    promote.mockResolvedValue({
      parent_project_id: 'parent-1',
      workflow_id: 'wf-parent',
    });

    const nav = stubNavigation();
    try {
      renderHeader({ isSandbox: true });

      await confirmPromote(user);
      const dialog = screen.getByRole('dialog');
      await waitFor(() => {
        expect(
          within(dialog).getByText('Changes promoted')
        ).toBeInTheDocument();
      });

      await user.click(
        within(dialog).getByRole('button', { name: 'Keep sandbox' })
      );

      await waitFor(() => {
        expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
      });
      // Staying in the sandbox: no archive push and no navigation.
      expect(archiveSandbox).not.toHaveBeenCalled();
      expect(nav.hrefSetter).not.toHaveBeenCalled();
      // The success toast is shown inline since we don't reload.
      expect(notifySuccess).toHaveBeenCalledWith(
        expect.objectContaining({ title: 'Workflow promoted' })
      );
    } finally {
      nav.restore();
    }
  });

  test('archiving the sandbox pushes archive_sandbox and navigates to the parent', async () => {
    const user = userEvent.setup();
    promote.mockResolvedValue({
      parent_project_id: 'parent-1',
      workflow_id: 'wf-parent',
    });
    archiveSandbox.mockResolvedValue({ parent_project_id: 'parent-1' });

    const nav = stubNavigation();
    try {
      renderHeader({ isSandbox: true });

      await confirmPromote(user);
      const dialog = screen.getByRole('dialog');
      await waitFor(() => {
        expect(
          within(dialog).getByText('Changes promoted')
        ).toBeInTheDocument();
      });

      await user.click(
        within(dialog).getByRole('button', { name: 'Archive sandbox' })
      );

      await waitFor(() => {
        expect(archiveSandbox).toHaveBeenCalledTimes(1);
      });
      // Navigation carries the promoted marker (the toast can't survive the
      // reload) and targets the parent's freshly merged workflow.
      await waitFor(() => {
        expect(nav.hrefSetter).toHaveBeenCalledWith(
          '/projects/parent-1/w/wf-parent?promoted=1'
        );
      });
      expect(notifySuccess).not.toHaveBeenCalled();
    } finally {
      nav.restore();
    }
  });

  test('hides the Archive action when the user cannot archive the sandbox', async () => {
    const user = userEvent.setup();
    canArchiveSandbox = false;
    promote.mockResolvedValue({
      parent_project_id: 'parent-1',
      workflow_id: 'wf-parent',
    });

    renderHeader({ isSandbox: true });

    await confirmPromote(user);
    const dialog = screen.getByRole('dialog');
    await waitFor(() => {
      expect(within(dialog).getByText('Changes promoted')).toBeInTheDocument();
    });

    // No Archive/Keep pair; only a plain close, plus the admin hint.
    expect(
      within(dialog).queryByRole('button', { name: 'Archive sandbox' })
    ).not.toBeInTheDocument();
    expect(
      within(dialog).queryByRole('button', { name: 'Keep sandbox' })
    ).not.toBeInTheDocument();
    expect(
      within(dialog).getByRole('button', { name: 'Done' })
    ).toBeInTheDocument();
    expect(
      within(dialog).getByText(/ask an admin to archive/i)
    ).toBeInTheDocument();
  });

  test('the confirm button shows a loading state while the merge is in flight', async () => {
    const user = userEvent.setup();
    // Never-resolving promise keeps the merge pending so the loading label stays.
    promote.mockReturnValue(new Promise(() => {}));

    renderHeader({ isSandbox: true });

    await confirmPromote(user);

    const dialog = screen.getByRole('dialog');
    const confirmButton = within(dialog).getByRole('button', {
      name: /Promoting/,
    });
    await waitFor(() => {
      expect(confirmButton).toBeDisabled();
    });
    // Still on phase one; the success step hasn't appeared.
    expect(
      within(dialog).queryByText('Changes promoted')
    ).not.toBeInTheDocument();
  });

  test('a failed save aborts the promote and alerts without advancing', async () => {
    const user = userEvent.setup();
    saveWorkflow.mockRejectedValue(new Error('save blew up'));

    renderHeader({ isSandbox: true });

    await confirmPromote(user);

    await waitFor(() => {
      expect(notifyAlert).toHaveBeenCalledWith(
        expect.objectContaining({ title: 'Could not save before promoting' })
      );
    });
    // The merge never runs, and the dialog stays on its confirm step.
    expect(promote).not.toHaveBeenCalled();
    const dialog = screen.getByRole('dialog');
    expect(
      within(dialog).getByText('Save and promote to parent project')
    ).toBeInTheDocument();
    expect(
      within(dialog).queryByText('Changes promoted')
    ).not.toBeInTheDocument();
  });

  test('a failed promote surfaces an alert without advancing to the success step', async () => {
    const user = userEvent.setup();
    promote.mockRejectedValue(
      new ChannelRequestError('unauthorized', {
        base: ['You are not allowed to promote this sandbox'],
      })
    );

    renderHeader({ isSandbox: true });

    await confirmPromote(user);

    await waitFor(() => {
      expect(notifyAlert).toHaveBeenCalledWith(
        expect.objectContaining({ title: 'Could not promote' })
      );
    });
    // The save succeeded first; only the merge failed. Still on phase one.
    expect(saveWorkflow).toHaveBeenCalledWith({ silent: true });
    const dialog = screen.getByRole('dialog');
    expect(
      within(dialog).queryByText('Changes promoted')
    ).not.toBeInTheDocument();
  });

  test('a failed archive alerts and leaves the success step open to retry', async () => {
    const user = userEvent.setup();
    promote.mockResolvedValue({
      parent_project_id: 'parent-1',
      workflow_id: 'wf-parent',
    });
    archiveSandbox.mockRejectedValue(
      new ChannelRequestError('unauthorized', {
        base: ['You are not allowed to archive this sandbox'],
      })
    );

    const nav = stubNavigation();
    try {
      renderHeader({ isSandbox: true });

      await confirmPromote(user);
      const dialog = screen.getByRole('dialog');
      await waitFor(() => {
        expect(
          within(dialog).getByText('Changes promoted')
        ).toBeInTheDocument();
      });

      await user.click(
        within(dialog).getByRole('button', { name: 'Archive sandbox' })
      );

      await waitFor(() => {
        expect(notifyAlert).toHaveBeenCalledWith(
          expect.objectContaining({ title: 'Could not archive sandbox' })
        );
      });
      // No navigation; the success step stays so the user can retry or keep.
      expect(nav.hrefSetter).not.toHaveBeenCalled();
      expect(
        within(dialog).getByRole('button', { name: 'Archive sandbox' })
      ).toBeInTheDocument();
    } finally {
      nav.restore();
    }
  });

  test('cancelling the Promote dialog closes it without saving or promoting', async () => {
    const user = userEvent.setup();
    renderHeader({ isSandbox: true });

    await user.click(screen.getByTestId('promote-sandbox-button'));
    const dialog = screen.getByRole('dialog');
    await user.click(within(dialog).getByRole('button', { name: 'Cancel' }));

    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
    expect(saveWorkflow).not.toHaveBeenCalled();
    expect(promote).not.toHaveBeenCalled();
  });
});

describe('Header - read-only reason variations', () => {
  beforeEach(() => {
    lifecycleState = 'live';
    isNewWorkflow = false;
    canProvisionSandbox = true;
    canArchiveSandbox = true;
    readOnly = { isReadOnly: false, reason: null };
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  test('shows the Create button for a new workflow held read-only as unsaved_new', () => {
    // A new workflow with canvas content is read-only with reason
    // 'unsaved_new'. That is exactly when the header primary action must be
    // shown so the user can create the workflow.
    lifecycleState = undefined;
    isNewWorkflow = true;
    readOnly = { isReadOnly: true, reason: 'unsaved_new' };

    renderHeader({ isSandbox: false });

    const saveButton = screen.getByTestId('save-workflow-button');
    expect(saveButton).toBeInTheDocument();
    expect(saveButton).toHaveTextContent('Create');
  });

  test('hides the Save button on a live read-only workflow', () => {
    // A true lock reason ('live') hides the primary action entirely.
    readOnly = { isReadOnly: true, reason: 'live' };

    renderHeader({ isSandbox: false });

    expect(
      screen.queryByTestId('save-workflow-button')
    ).not.toBeInTheDocument();
  });

  test('keeps the Read-only cue on a pinned old version of a live workflow', () => {
    // On a pinned old version of a currently-live workflow, "Live" (the
    // current state) doesn't explain why the view is read-only, so the
    // Read-only cue must still show.
    readOnly = { isReadOnly: true, reason: 'pinned_version' };

    renderHeader({ isSandbox: false });

    expect(screen.getByTestId('read-only-warning')).toBeInTheDocument();
  });

  test('suppresses the redundant Read-only cue on the current live version', () => {
    // The Live badge already implies read-only for the current live version,
    // so the redundant Read-only cue stays hidden.
    readOnly = { isReadOnly: true, reason: 'live' };

    renderHeader({ isSandbox: false });

    expect(screen.queryByTestId('read-only-warning')).not.toBeInTheDocument();
  });
});

describe('Header - long workflow name', () => {
  beforeEach(() => {
    lifecycleState = 'live';
    isNewWorkflow = false;
    canProvisionSandbox = true;
    canArchiveSandbox = true;
    readOnly = { isReadOnly: false, reason: null };
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
