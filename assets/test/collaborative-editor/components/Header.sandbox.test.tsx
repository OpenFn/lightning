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
let experimentalFeatures = true;
let workflowEnabled: boolean | null = true;
const setEnabled = vi.fn();
let isNewWorkflow = false;
let canProvisionSandbox = true;
let limits: Record<string, { allowed: boolean; message: string | null }> = {};
let canArchiveSandbox = true;
let readOnly: {
  isReadOnly: boolean;
  reason:
    | 'deleted'
    | 'live'
    | 'no_permission'
    | 'pinned_version'
    | 'as_run'
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
const checkPromote =
  vi.fn<() => Promise<{ diverged: boolean; parent_name: string | null }>>();

let urlParams: Record<string, string> = {};
const updateSearchParams = vi.fn();
let activeRun: {
  id: string;
  state: string;
  steps: { id: string; input_dataclip_id?: string }[];
} | null = null;
let latestSnapshotId: string | null = null;
let workflowTriggers: { id: string }[] = [];
let activeRunSummary: { id: string; snapshot_id: string | null } | undefined;
// The lifecycle lock, which decides whether a run saves on its way out.
let contentLocked = false;
// The session context has landed. The header withholds what depends on it
// until it has, so a test about that has to be able to turn it off.
let sessionContextLoaded = true;
let releases: {
  version_number: number;
  snapshot_id: string | null;
}[] = [];

vi.mock('../../../js/react/lib/use-url-state', () => ({
  useURLState: () => ({ params: urlParams, updateSearchParams }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useHistory', () => ({
  useActiveRun: () => activeRun,
  // The header asks which snapshot the loaded run executed, to decide whether
  // it can come along into a draft.
  useRunSummary: () => activeRunSummary,
}));

vi.mock('../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: () => ({ provider: null, isSynced: true, settled: true }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useSessionContextLoaded: () => sessionContextLoaded,
  useRequestVersions: () => vi.fn(),
  useVersionsError: () => null,
  useVersionsLoading: () => false,
  useVersionsLoaded: () => true,
  useVersions: () => [],
  useIsNewWorkflow: () => isNewWorkflow,
  useLimits: () => limits,
  usePermissions: () => ({
    can_provision_sandbox: canProvisionSandbox,
    can_archive_sandbox: canArchiveSandbox,
  }),
  useContentLocked: () => contentLocked,
  useProjectRepoConnection: () => null,
  useLatestSnapshotId: () => latestSnapshotId,
  useReleases: () => releases,
  useSessionWorkflow: () => ({ state: lifecycleState }),
  // Defaults on, because most of these tests are about the experimental
  // experience. The gating tests turn it off.
  useExperimentalFeatures: () => experimentalFeatures,
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
  useWorkflowEnabled: () => ({ enabled: workflowEnabled, setEnabled }),
  useCanRun: () => ({ canRun: true }),
  // Saving follows the read-only state in the app, so the stub follows it here
  // too. Leaving it permanently true would let a test assert a Save button that
  // could not exist.
  useCanSave: () => ({
    canSave: !readOnly.isReadOnly,
    tooltipMessage: readOnly.reason ?? '',
  }),
  useNodeSelection: () => ({ selectNode: vi.fn() }),
  useWorkflowActions: () => ({
    saveWorkflow,
    goLive,
    switchToDraft,
    listSandboxes: vi.fn(),
    editInSandbox: vi.fn(),
    promote,
    checkPromote,
    archiveSandbox,
  }),
  useWorkflowReadOnly: () => readOnly,
  useWorkflowSettingsErrors: () => ({ hasErrors: false }),
  useWorkflowState: (selector: (state: unknown) => unknown) =>
    selector({ triggers: workflowTriggers, jobs: [] }),
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
  // Carries the label and the disabled state through, because whether this
  // reads Run or Run (Retry), and whether it is usable, is the thing under test.
  NewRunButton: ({ text, disabled }: { text?: string; disabled?: boolean }) => (
    <button type="button" data-testid="new-run-button" disabled={disabled}>
      {text}
    </button>
  ),
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
    sessionContextLoaded = true;
    lifecycleState = 'live';
    isNewWorkflow = false;
    canProvisionSandbox = true;
    experimentalFeatures = true;
    workflowEnabled = true;
    setEnabled.mockReset();
    canArchiveSandbox = true;
    limits = {};
    readOnly = { isReadOnly: false, reason: null };
    urlParams = {};
    activeRun = null;
    activeRunSummary = undefined;
    sessionContextLoaded = true;
    latestSnapshotId = null;
    releases = [];
    updateSearchParams.mockClear();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  test('shows an enabled button when the user can provision a sandbox', () => {
    renderHeader({ isSandbox: false });
    const button = screen.getByTestId('edit-in-sandbox-button');
    expect(button).toBeEnabled();
    // The Tooltip renders bare children when content is null, so nothing here
    // is a Radix trigger when provisioning is allowed.
    expect(button).not.toHaveAttribute('data-state');
    expect(button.parentElement).not.toHaveAttribute('data-state');
  });

  test('renders the button disabled and tooltip-wrapped when provisioning is not allowed', () => {
    canProvisionSandbox = false;
    renderHeader({ isSandbox: false });

    const button = screen.getByTestId('edit-in-sandbox-button');
    expect(button).toBeDisabled();
    // A disabled button dispatches no pointer events, so the Radix trigger has
    // to be the wrapper around it rather than the button itself.
    expect(button.parentElement).toHaveAttribute('data-state');
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
    sessionContextLoaded = true;
    lifecycleState = 'live';
    isNewWorkflow = false;
    canProvisionSandbox = true;
    experimentalFeatures = true;
    workflowEnabled = true;
    setEnabled.mockReset();
    canArchiveSandbox = true;
    limits = {};
    urlParams = {};
    readOnly = { isReadOnly: false, reason: null };
    goLive.mockReset();
    switchToDraft.mockReset();
    saveWorkflow.mockReset();
    promote.mockReset();
    archiveSandbox.mockReset();
    checkPromote.mockReset();
    checkPromote.mockResolvedValue({ diverged: false, parent_name: null });
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

  test('keeps the on/off switch for a user without experimental features', () => {
    // Their only way to turn a workflow on or off. With the flag on, the
    // lifecycle badge and Go live / Switch to draft answer the same question,
    // so the switch would be a second, contradicting control.
    experimentalFeatures = false;
    workflowEnabled = true;

    renderHeader();

    const toggle = screen.getByRole('switch');
    expect(toggle).toBeInTheDocument();
    expect(toggle).toBeChecked();
  });

  test('drops the switch once experimental features are on', () => {
    experimentalFeatures = true;
    lifecycleState = 'live';

    renderHeader();

    expect(screen.queryByRole('switch')).not.toBeInTheDocument();
    expect(screen.getByTestId('workflow-lifecycle-badge')).toBeInTheDocument();
  });

  test('shows none of it to a user without experimental features', () => {
    // The point of the flag: a user who has not turned it on gets the header
    // they had before. Everything the sandboxes-and-releases work added is
    // guarded by the lifecycle state or by being inside a sandbox, so the flag
    // reads both as absent rather than each button testing it separately.
    //
    // The workflow really is live in the database here, which is the case that
    // matters: a colleague with the flag on can publish a shared workflow.
    experimentalFeatures = false;
    lifecycleState = 'live';

    renderHeader();

    expect(
      screen.queryByTestId('workflow-lifecycle-badge')
    ).not.toBeInTheDocument();
    expect(
      screen.queryByTestId('edit-in-sandbox-button')
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole('button', { name: 'Switch to draft' })
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole('button', { name: 'Go live' })
    ).not.toBeInTheDocument();
    expect(screen.queryByTestId('retry-run-button')).not.toBeInTheDocument();
  });

  test('shows none of it inside a sandbox either, without the flag', () => {
    experimentalFeatures = false;
    lifecycleState = 'draft';

    renderHeader({ isSandbox: true });

    expect(
      screen.queryByTestId('toggle-sandbox-button')
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole('button', { name: 'Promote' })
    ).not.toBeInTheDocument();
    expect(
      screen.queryByTestId('workflow-lifecycle-badge')
    ).not.toBeInTheDocument();
  });

  test('hides the Live badge when viewing a pinned older version', () => {
    // The workflow is live, but we are pinned to a release (?v=), so the
    // current "Live" state does not describe what's on screen.
    lifecycleState = 'live';
    urlParams = { v: '2' };

    renderHeader();

    expect(
      screen.queryByTestId('workflow-lifecycle-badge')
    ).not.toBeInTheDocument();
  });

  test('refuses the lifecycle and sandbox actions on a pinned older version', () => {
    // They all act on the current workflow, so pressing one here would reach
    // past what is on screen. They stay put and say so: hiding them left a
    // header with nothing in it and nothing to explain the view.
    lifecycleState = 'live';
    urlParams = { v: '2' };

    renderHeader();

    expect(screen.getByTestId('switch-to-draft-button')).toBeDisabled();
    expect(screen.getByTestId('edit-in-sandbox-button')).toBeDisabled();
  });

  test('refuses Go live on a pinned older version of a draft workflow', () => {
    // It acts on the current workflow, not the version being read, so it stays
    // on screen and says so rather than vanishing.
    lifecycleState = 'draft';
    urlParams = { v: '2' };

    renderHeader({ isSandbox: false });

    expect(screen.getByTestId('go-live-button')).toBeDisabled();
  });

  test('keeps the two ways to edit while reading a run', () => {
    lifecycleState = 'live';
    urlParams = { as_run: 'run-123', run: 'run-123' };

    renderHeader();

    // Reading a failed run is where the fix starts, and these are the only two
    // ways to edit a live workflow. Hiding them left the journey with no exit,
    // since leaving the run first loses the run and its input with it.
    expect(screen.getByTestId('switch-to-draft-button')).toBeInTheDocument();
    expect(screen.getByTestId('edit-in-sandbox-button')).toBeInTheDocument();
  });

  test('refuses them on a pinned version, rather than hiding them', () => {
    lifecycleState = 'live';
    urlParams = { v: '2' };

    renderHeader();

    // No run here to carry into a fix, so this stays a reading view. The
    // controls stay put and say why, because a header with nothing in it
    // explains nothing.
    expect(screen.getByTestId('switch-to-draft-button')).toBeDisabled();
  });

  test('offers the actions again on the current version', () => {
    lifecycleState = 'live';
    urlParams = {};

    renderHeader();

    expect(screen.getByTestId('switch-to-draft-button')).toBeInTheDocument();
    expect(screen.getByTestId('edit-in-sandbox-button')).toBeInTheDocument();
  });

  test('hides the Live badge in an as-executed run view', () => {
    lifecycleState = 'live';
    urlParams = { as_run: 'run-123' };

    renderHeader();

    expect(
      screen.queryByTestId('workflow-lifecycle-badge')
    ).not.toBeInTheDocument();
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

  test('go live requires confirmation before running', async () => {
    const user = userEvent.setup();
    lifecycleState = 'draft';
    renderHeader();

    await user.click(screen.getByTestId('go-live-button'));

    // Turning the triggers on and starting to process real data is the most
    // consequential thing here, and it was the only one that fired straight
    // from the click.
    expect(goLive).not.toHaveBeenCalled();

    await user.click(
      within(screen.getByRole('dialog')).getByRole('button', {
        name: 'Go live',
      })
    );

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

  test("switching to draft from a run carries the run and its input", async () => {
    const user = userEvent.setup();
    lifecycleState = 'live';
    urlParams = { run: 'run-1', as_run: 'run-1' };
    activeRun = {
      id: 'run-1',
      state: 'failed',
      steps: [{ id: 'step-1', input_dataclip_id: 'dc-7' }],
    };
    // This run executed the content that is live, so it still describes what
    // the draft opens on.
    latestSnapshotId = 'snapshot-live';
    activeRunSummary = { id: 'run-1', snapshot_id: 'snapshot-live' };

    renderHeader();

    await user.click(screen.getByTestId('switch-to-draft-button'));
    await user.click(
      within(screen.getByRole('dialog')).getByRole('button', {
        name: 'Switch to draft',
      })
    );

    // Switching to draft unlocks the content, it does not change it, so the run
    // still describes what is on screen. Dropping it threw away the logs and
    // the failing step at the moment the fix starts. Every pinned parameter
    // goes, because only the latest version can be edited.
    await waitFor(() => {
      expect(updateSearchParams).toHaveBeenCalledWith({
        release: null,
        v: null,
        as_run: null,
        step: null,
        run: 'run-1',
        panel: 'run',
        dataclip: 'dc-7',
      });
    });
  });

  test('switching to draft carries a run of older content too', async () => {
    const user = userEvent.setup();
    lifecycleState = 'live';
    urlParams = { run: 'run-1', as_run: 'run-1' };
    activeRun = {
      id: 'run-1',
      state: 'failed',
      steps: [{ id: 'step-1', input_dataclip_id: 'dc-7' }],
    };
    latestSnapshotId = 'snapshot-live';
    activeRunSummary = { id: 'run-1', snapshot_id: 'snapshot-older' };

    renderHeader();

    await user.click(screen.getByTestId('switch-to-draft-button'));
    await user.click(
      within(screen.getByRole('dialog')).getByRole('button', {
        name: 'Switch to draft',
      })
    );

    // It lands on the latest version, which is the only editable one, and the
    // version banner says the run took place on something else. Dropping it
    // instead took away the logs the fix is being written against.
    await waitFor(() => {
      expect(updateSearchParams).toHaveBeenCalledWith({
        release: null,
        v: null,
        as_run: null,
        step: null,
        run: 'run-1',
        panel: 'run',
        dataclip: 'dc-7',
      });
    });
  });

  test('switching to draft with no run loaded carries nothing', async () => {
    const user = userEvent.setup();
    lifecycleState = 'live';
    urlParams = {};
    activeRun = null;
    activeRunSummary = undefined;
    sessionContextLoaded = true;

    renderHeader();

    await user.click(screen.getByTestId('switch-to-draft-button'));
    await user.click(
      within(screen.getByRole('dialog')).getByRole('button', {
        name: 'Switch to draft',
      })
    );

    await waitFor(() => {
      expect(updateSearchParams).toHaveBeenCalledWith({
        release: null,
        v: null,
        as_run: null,
        step: null,
        run: null,
      });
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

  describe('turning a sandbox on and off', () => {
    test('offers Turn on while the sandbox is a draft', () => {
      lifecycleState = 'draft';
      renderHeader({ isSandbox: true });

      const button = screen.getByTestId('toggle-sandbox-button');
      expect(button).toBeEnabled();
      expect(button).toHaveTextContent('Turn on');
    });

    test('turning it on goes through the same lifecycle transition as going live', async () => {
      lifecycleState = 'draft';
      const user = userEvent.setup();
      renderHeader({ isSandbox: true });

      await user.click(screen.getByTestId('toggle-sandbox-button'));

      // Same transition, so it respects the activation limit and records a
      // release exactly as the parent's Go live does.
      await waitFor(() => {
        expect(goLive).toHaveBeenCalledTimes(1);
      });
      expect(switchToDraft).not.toHaveBeenCalled();
    });

    test('offers Turn off once the sandbox is on', () => {
      lifecycleState = 'live';
      renderHeader({ isSandbox: true });

      expect(screen.getByTestId('toggle-sandbox-button')).toHaveTextContent(
        'Turn off'
      );
    });

    test('turning it off switches it back to draft, with no confirmation', async () => {
      lifecycleState = 'live';
      const user = userEvent.setup();
      renderHeader({ isSandbox: true });

      await user.click(screen.getByTestId('toggle-sandbox-button'));

      // Nothing in production is affected, so there is nothing to confirm.
      await waitFor(() => {
        expect(switchToDraft).toHaveBeenCalledTimes(1);
      });
      expect(goLive).not.toHaveBeenCalled();
    });

    test('a failed transition says so and leaves the button usable', async () => {
      lifecycleState = 'draft';
      goLive.mockRejectedValue(new Error('nope'));
      const user = userEvent.setup();
      renderHeader({ isSandbox: true });

      await user.click(screen.getByTestId('toggle-sandbox-button'));

      await waitFor(() => {
        expect(notifyAlert).toHaveBeenCalledWith(
          expect.objectContaining({
            title: 'Could not turn the sandbox on',
          })
        );
      });
      await waitFor(() => {
        expect(screen.getByTestId('toggle-sandbox-button')).toBeEnabled();
      });
    });

    test('is not offered outside a sandbox', () => {
      lifecycleState = 'draft';
      renderHeader({ isSandbox: false });

      expect(
        screen.queryByTestId('toggle-sandbox-button')
      ).not.toBeInTheDocument();
    });

    test('is refused on a pinned version of a sandbox', () => {
      // It turns the sandbox on, which is about the workflow now, not the
      // version being read. It stays on screen and says so.
      lifecycleState = 'draft';
      urlParams = { v: '2' };

      renderHeader({ isSandbox: true });

      expect(screen.getByTestId('toggle-sandbox-button')).toBeDisabled();
    });
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

  test('holds the promote until the divergence check has answered', async () => {
    const user = userEvent.setup();
    let resolveCheck: (value: {
      diverged: boolean;
      parent_name: string | null;
    }) => void = () => {};
    checkPromote.mockReturnValue(
      new Promise(resolve => {
        resolveCheck = resolve;
      })
    );
    renderHeader({ isSandbox: true });

    await user.click(screen.getByTestId('promote-sandbox-button'));

    const dialog = screen.getByRole('dialog');
    expect(
      within(dialog).getByRole('button', { name: 'Save and promote' })
    ).toBeDisabled();
    expect(
      within(dialog).getByText(/checking whether the parent has changed/i)
    ).toBeInTheDocument();

    resolveCheck({ diverged: false, parent_name: null });

    await waitFor(() => {
      expect(
        within(dialog).getByRole('button', { name: 'Save and promote' })
      ).toBeEnabled();
    });
  });

  test('warns on the confirm step when the parent has changed since the fork', async () => {
    const user = userEvent.setup();
    checkPromote.mockResolvedValue({
      diverged: true,
      parent_name: 'Production',
    });
    renderHeader({ isSandbox: true });

    await user.click(screen.getByTestId('promote-sandbox-button'));

    const dialog = screen.getByRole('dialog');
    expect(
      await within(dialog).findByText(/has changed in/i)
    ).toBeInTheDocument();
    expect(within(dialog).getByText('Production')).toBeInTheDocument();
    expect(
      within(dialog).getByRole('button', { name: 'Save and promote' })
    ).toBeEnabled();
  });

  test('shows no divergence warning when the parent has not moved on', async () => {
    const user = userEvent.setup();
    renderHeader({ isSandbox: true });

    await user.click(screen.getByTestId('promote-sandbox-button'));

    await waitFor(() => {
      expect(checkPromote).toHaveBeenCalledTimes(1);
    });
    expect(screen.queryByText(/has changed in/i)).not.toBeInTheDocument();
  });

  test('a failed divergence check leaves the dialog usable', async () => {
    const user = userEvent.setup();
    checkPromote.mockRejectedValue(new Error('channel down'));
    renderHeader({ isSandbox: true });

    await user.click(screen.getByTestId('promote-sandbox-button'));

    await waitFor(() => {
      expect(checkPromote).toHaveBeenCalledTimes(1);
    });

    const dialog = screen.getByRole('dialog');
    expect(
      within(dialog).getByRole('button', { name: 'Save and promote' })
    ).toBeEnabled();
    expect(
      within(dialog).queryByText(/has changed in/i)
    ).not.toBeInTheDocument();
    expect(
      within(dialog).getByText(
        /could not check whether the parent has changed/i
      )
    ).toBeInTheDocument();
  });

  test('reopening the dialog re-runs the check and clears a stale warning', async () => {
    const user = userEvent.setup();
    checkPromote.mockResolvedValue({
      diverged: true,
      parent_name: 'Production',
    });
    renderHeader({ isSandbox: true });

    await user.click(screen.getByTestId('promote-sandbox-button'));
    expect(
      await within(screen.getByRole('dialog')).findByText(/has changed in/i)
    ).toBeInTheDocument();

    await user.click(
      within(screen.getByRole('dialog')).getByRole('button', { name: 'Cancel' })
    );

    checkPromote.mockResolvedValue({ diverged: false, parent_name: null });
    await user.click(screen.getByTestId('promote-sandbox-button'));

    await waitFor(() => {
      expect(checkPromote).toHaveBeenCalledTimes(2);
    });
    expect(screen.queryByText(/has changed in/i)).not.toBeInTheDocument();
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
      expect(saveWorkflow).toHaveBeenCalledWith({ notify: 'none' });
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

  test('archiving the sandbox pushes archive_sandbox and leaves navigation to the server', async () => {
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
      // Archiving schedules the sandbox for deletion, and the LiveView teardown
      // hook redirects every socket on it to the parent's copy of this
      // workflow. Navigating from here as well only raced that redirect.
      expect(nav.hrefSetter).not.toHaveBeenCalled();
      expect(notifySuccess).not.toHaveBeenCalled();

      // The reload would destroy a toast raised here, and the flash the server
      // sends on arrival speaks only of the archive. The promote is handed
      // across instead, for the parent's editor to confirm.
      expect(window.sessionStorage.getItem('openfn:promoted')).toBe('1');
    } finally {
      nav.restore();
      window.sessionStorage.removeItem('openfn:promoted');
    }
  });

  test('a refused archive claims no promote across the reload', async () => {
    // Nothing navigates, so the marker would sit there and announce a promote
    // to the next page this tab happens to load.
    const user = userEvent.setup();
    promote.mockResolvedValue({
      parent_project_id: 'parent-1',
      workflow_id: 'wf-parent',
    });
    archiveSandbox.mockRejectedValue(new Error('nope'));

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

      expect(window.sessionStorage.getItem('openfn:promoted')).toBeNull();
    } finally {
      nav.restore();
      window.sessionStorage.removeItem('openfn:promoted');
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
    expect(saveWorkflow).toHaveBeenCalledWith({ notify: 'none' });
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
    sessionContextLoaded = true;
    lifecycleState = 'live';
    isNewWorkflow = false;
    canProvisionSandbox = true;
    experimentalFeatures = true;
    workflowEnabled = true;
    setEnabled.mockReset();
    canArchiveSandbox = true;
    limits = {};
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

  test('drops Save on a live workflow, where it could never work', () => {
    // The Live badge and Switch to draft sit beside it and explain the state,
    // so a permanently dead button adds nothing.
    readOnly = { isReadOnly: true, reason: 'live' };

    renderHeader({ isSandbox: false });

    expect(screen.queryByTestId('save-workflow-button')).toBeNull();
  });

  test('withholds Save until the session context has landed', () => {
    // The flag arrives with the context, so until it does "flag off" and "we do
    // not know" look the same. Rendering Save on that guess and taking it away
    // a moment later is the flicker this avoids.
    sessionContextLoaded = false;
    lifecycleState = 'draft';

    renderHeader({ isSandbox: false });

    expect(screen.queryByTestId('save-workflow-button')).toBeNull();
  });

  test('keeps Save, disabled, on a live workflow without the flag', () => {
    // Nothing on screen explains the state without the flag, so the button
    // stays and carries the reason, as it does on main.
    experimentalFeatures = false;
    readOnly = { isReadOnly: true, reason: 'live' };

    renderHeader({ isSandbox: false });

    expect(screen.getByTestId('save-workflow-button')).toBeDisabled();
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
    sessionContextLoaded = true;
    lifecycleState = 'live';
    isNewWorkflow = false;
    canProvisionSandbox = true;
    experimentalFeatures = true;
    workflowEnabled = true;
    setEnabled.mockReset();
    canArchiveSandbox = true;
    limits = {};
    readOnly = { isReadOnly: false, reason: null };
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  test('truncates a long workflow name so the save action stays visible', () => {
    // A draft, because that is where Save exists to be crowded out.
    lifecycleState = 'draft';
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

describe('Header - retry from a run view', () => {
  beforeEach(() => {
    sessionContextLoaded = true;
    lifecycleState = 'live';
    isNewWorkflow = false;
    limits = {};
    // Reading a run as it executed, which is read-only.
    readOnly = { isReadOnly: true, reason: 'as_run' };
    urlParams = { run: 'run-1', as_run: 'run-1' };
    activeRun = { id: 'run-1', state: 'failed', steps: [{ id: 'step-1' }] };
    latestSnapshotId = 'snapshot-live';
    releases = [{ version_number: 4, snapshot_id: 'snapshot-live' }];
    workflowTriggers = [{ id: 'trigger-1' }];
  });

  afterEach(() => {
    workflowTriggers = [];
    vi.clearAllMocks();
  });

  test('offers a retry while reading a run as it executed', () => {
    renderHeader({ isSandbox: false });

    const runButton = screen.getByTestId('new-run-button');
    expect(runButton).toHaveTextContent('Run (Retry)');
    expect(runButton).toBeEnabled();
  });

  test('offers it for a run of the live content too', () => {
    // No as_run: this run executed what is live, so it overlays on the live
    // document.
    urlParams = { run: 'run-1' };
    readOnly = { isReadOnly: true, reason: 'live' };

    renderHeader({ isSandbox: false });

    const runButton = screen.getByTestId('new-run-button');
    expect(runButton).toHaveTextContent('Run (Retry)');
    expect(runButton).toBeEnabled();
  });

  test('offers the retry even though the view is read-only', () => {
    renderHeader({ isSandbox: false });

    // Retrying is an execution, not an edit. Blocking it with the read-only
    // lock took away the only way to clear a failed work order from here.
    const runButton = screen.getByTestId('new-run-button');
    expect(runButton).toHaveTextContent('Run (Retry)');
    expect(runButton).toBeEnabled();
  });

  test('does not offer a retry while the run is still going', () => {
    activeRun = { id: 'run-1', state: 'started', steps: [{ id: 'step-1' }] };

    renderHeader({ isSandbox: false });

    // The control is still there to start a fresh run; it just is not a retry.
    expect(screen.getByTestId('new-run-button')).toHaveTextContent('Run');
    expect(screen.getByTestId('new-run-button')).not.toHaveTextContent(
      'Retry'
    );
  });

  test('does not offer a retry with no run loaded', () => {
    urlParams = {};
    activeRun = null;
    activeRunSummary = undefined;
    sessionContextLoaded = true;
    readOnly = { isReadOnly: false, reason: null };

    renderHeader({ isSandbox: false });

    // The control is still there to start a fresh run; it just is not a retry.
    expect(screen.getByTestId('new-run-button')).toHaveTextContent('Run');
    expect(screen.getByTestId('new-run-button')).not.toHaveTextContent(
      'Retry'
    );
  });
});
