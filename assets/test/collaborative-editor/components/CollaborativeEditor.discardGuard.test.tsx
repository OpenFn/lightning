/**
 * Unsaved-changes guard wiring tests
 *
 * The hook tests cover `useDiscardGuard` in isolation. These render the real
 * breadcrumbs with the real `useVersionSelect`, because the first version of
 * this feature shipped a guard that worked in isolation and never rendered:
 * the dialog sat inside a `useMemo` whose dependencies did not include the
 * prompt, so picking a version with unsaved edits did nothing at all.
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { BreadcrumbContent } from '../../../js/collaborative-editor/CollaborativeEditor';
import { Breadcrumbs as ActualBreadcrumbs } from '../../../js/collaborative-editor/components/Breadcrumbs';
import { KeyboardProvider } from '../../../js/collaborative-editor/keyboard';
import {
  createMockURLState,
  getURLStateMockValue,
} from '../__helpers__/urlStateMocks';

const urlState = createMockURLState();

let hasChanges = false;
let isSynced = true;
// The guard forgets it ever synced only when the document is replaced, which it
// reads off the provider's identity.
let provider: object | null = { id: 'provider-1' };
const saveWorkflow = vi.fn<() => Promise<unknown>>();

vi.mock('#/react/lib/use-url-state', () => ({
  useURLState: () => getURLStateMockValue(urlState),
}));

vi.mock('../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: () => ({ provider, isSynced }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useUnsavedChanges', () => ({
  useUnsavedChanges: () => ({ hasChanges }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowActions: () => ({
    saveWorkflow,
    restoreVersion: vi.fn(),
    checkRestore: vi.fn(() => new Promise(() => {})),
  }),
  useWorkflowState: (selector: (state: unknown) => unknown) => {
    const state = { workflow: { id: 'workflow-1', lock_version: 1 } };
    return typeof selector === 'function' ? selector(state) : state;
  },
}));

// BreadcrumbContent lives in CollaborativeEditor.tsx, whose module graph
// reaches Monaco. Stub the heavy siblings so importing it stays cheap.
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

// Header is heavy, but its Breadcrumbs are the thing BreadcrumbContent has a
// contract with: they treat their last child as the workflow title. So the stub
// keeps the real Breadcrumbs, and a stray extra child shows up as a mangled
// crumb list rather than passing silently.
vi.mock('../../../js/collaborative-editor/components/Header', () => ({
  Header: ({ children }: { children: React.ReactNode[] }) => (
    <div data-testid="header">
      <ActualBreadcrumbs>{children}</ActualBreadcrumbs>
    </div>
  ),
}));

// A real trigger for the real hook, so the wiring between them is under test.
vi.mock('../../../js/collaborative-editor/components/VersionDropdown', () => ({
  VersionDropdown: ({
    onVersionSelect,
  }: {
    onVersionSelect: (version: number | 'latest') => void;
  }) => (
    <button
      data-testid="pick-version-3"
      onClick={() => {
        onVersionSelect(3);
      }}
    >
      Versions
    </button>
  ),
}));

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useProject: () => ({ id: 'project-1', name: 'Test Project' }),
  useLatestSnapshotLockVersion: () => 1,
  useIsNewWorkflow: () => false,
  usePermissions: () => ({ can_edit_workflow: true }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useUI', () => ({
  useIsRunPanelOpen: () => true,
  useUICommands: () => ({ closeRunPanel: vi.fn() }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useHistory', () => ({
  useHistoryCommands: () => ({ closeRunViewer: vi.fn() }),
}));

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

describe('unsaved-changes guard, wired up', () => {
  beforeEach(() => {
    urlState.reset();
    hasChanges = false;
    isSynced = true;
    provider = { id: 'provider-1' };
    saveWorkflow.mockReset();
    saveWorkflow.mockResolvedValue(undefined);
  });

  test('the dialog does not take the workflow title slot in the breadcrumbs', () => {
    renderBreadcrumbs();

    // Breadcrumbs render their last child as the title and the rest as crumbs.
    // Put the dialog in that array and the project, Workflows and the workflow
    // name collapse into one crumb with no chevron between them.
    expect(screen.getByText('Test Workflow')).toBeInTheDocument();
    expect(screen.getByText('Workflows')).toBeInTheDocument();
    expect(screen.getByText('Workflows').closest('li')).not.toContainElement(
      screen.getByText('Test Workflow')
    );
  });

  test('picking a version with unsaved edits opens the dialog and switches nothing', async () => {
    hasChanges = true;
    const user = userEvent.setup();
    renderBreadcrumbs();

    await user.click(screen.getByTestId('pick-version-3'));

    expect(
      await screen.findByTestId('discard-changes-dialog')
    ).toBeInTheDocument();
    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalled();
  });

  test('picking a version with nothing unsaved switches straight away', async () => {
    const user = userEvent.setup();
    renderBreadcrumbs();

    await user.click(screen.getByTestId('pick-version-3'));

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      release: '3',
      v: null,
      run: null,
      as_run: null,
      step: null,
    });
    expect(
      screen.queryByTestId('discard-changes-dialog')
    ).not.toBeInTheDocument();
  });

  test('Switch discards and goes', async () => {
    hasChanges = true;
    const user = userEvent.setup();
    renderBreadcrumbs();

    await user.click(screen.getByTestId('pick-version-3'));
    await user.click(await screen.findByRole('button', { name: 'Switch' }));

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      release: '3',
      v: null,
      run: null,
      as_run: null,
      step: null,
    });
  });

  test('Save and switch saves first', async () => {
    hasChanges = true;
    const user = userEvent.setup();
    renderBreadcrumbs();

    await user.click(screen.getByTestId('pick-version-3'));
    await user.click(
      await screen.findByRole('button', { name: 'Save and switch' })
    );

    await waitFor(() => {
      expect(saveWorkflow).toHaveBeenCalledWith({ notify: 'error-only' });
    });
    await waitFor(() => {
      expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
        release: '3',
        v: null,
        run: null,
        as_run: null,
        step: null,
      });
    });
  });

  test('the dialog is usable again after a successful save and switch', async () => {
    hasChanges = true;
    const user = userEvent.setup();
    renderBreadcrumbs();

    await user.click(screen.getByTestId('pick-version-3'));
    await user.click(
      await screen.findByRole('button', { name: 'Save and switch' })
    );
    await waitFor(() => {
      expect(saveWorkflow).toHaveBeenCalled();
    });

    // Nothing unmounts the dialog: the version switch rewrites the URL rather
    // than navigating, so it has to clear its own in-flight state.
    await user.click(screen.getByTestId('pick-version-3'));

    const cancel = await screen.findByRole('button', { name: 'Cancel' });
    expect(cancel).toBeEnabled();
    expect(screen.getByRole('button', { name: 'Switch' })).toBeEnabled();
    expect(
      screen.getByRole('button', { name: 'Save and switch' })
    ).toBeEnabled();
  });

  test('a dropped connection does not disarm the guard', async () => {
    hasChanges = true;
    const user = userEvent.setup();
    const { rerender } = renderBreadcrumbs();

    // First sync happened; then the websocket drops without the document being
    // replaced, which is when unsaved work is most at risk.
    isSynced = false;
    rerender(
      <KeyboardProvider>
        <BreadcrumbContent
          workflowId="workflow-1"
          workflowName="Test Workflow"
          aiAssistantEnabled={false}
        />
      </KeyboardProvider>
    );

    await user.click(screen.getByTestId('pick-version-3'));

    expect(
      await screen.findByTestId('discard-changes-dialog')
    ).toBeInTheDocument();
    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalled();
  });

  test('a replaced document forgets the earlier sync', async () => {
    hasChanges = true;
    const user = userEvent.setup();
    const { rerender } = renderBreadcrumbs();

    // A new provider means a new document. Its store is still empty, so it
    // differs from the saved workflow through no fault of the person.
    provider = { id: 'provider-2' };
    isSynced = false;
    rerender(
      <KeyboardProvider>
        <BreadcrumbContent
          workflowId="workflow-1"
          workflowName="Test Workflow"
          aiAssistantEnabled={false}
        />
      </KeyboardProvider>
    );

    await user.click(screen.getByTestId('pick-version-3'));

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalled();
    expect(
      screen.queryByTestId('discard-changes-dialog')
    ).not.toBeInTheDocument();
  });

  test('a document that has never synced does not prompt', async () => {
    hasChanges = true;
    isSynced = false;
    const user = userEvent.setup();
    renderBreadcrumbs();

    await user.click(screen.getByTestId('pick-version-3'));

    // An unsynced store is empty and so differs from the saved workflow, which
    // is not a change anyone made.
    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalled();
    expect(
      screen.queryByTestId('discard-changes-dialog')
    ).not.toBeInTheDocument();
  });
});
