/**
 * Workflow Title Breadcrumb Tests
 *
 * The workflow title in the editor breadcrumbs returns to the root workflow
 * editor view: it closes the full IDE (and any other panel), deselects the
 * current node, and drops any run-viewing context, landing on the bare canvas.
 *
 * The run panel and the run viewer live in stores as well as the URL, and each
 * has a sync effect that writes its param straight back if only the URL is
 * cleared (WorkflowEditor restores panel=run, CollaborativeWorkflowDiagram
 * restores run=<id>). So these tests assert that the handler closes both at the
 * source, not just that it passes the right params.
 *
 * Breadcrumbs.test.tsx covers the BreadcrumbLink/BreadcrumbText primitives.
 */

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { BreadcrumbContent } from '../../../js/collaborative-editor/CollaborativeEditor';
import {
  createMockURLState,
  getURLStateMockValue,
} from '../__helpers__/urlStateMocks';

const urlState = createMockURLState();
const closeRunPanel = vi.fn();
const closeRunViewer = vi.fn();

vi.mock('#/react/lib/use-url-state', () => ({
  useURLState: () => getURLStateMockValue(urlState),
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

vi.mock('../../../js/collaborative-editor/components/Header', () => ({
  Header: ({ children }: { children: React.ReactNode }) => (
    <div data-testid="header">{children}</div>
  ),
}));

vi.mock('../../../js/collaborative-editor/components/VersionDropdown', () => ({
  VersionDropdown: () => <div data-testid="version-dropdown">Versions</div>,
}));

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useProject: () => ({ id: 'project-1', name: 'Test Project' }),
  useLatestSnapshotLockVersion: () => 1,
  useIsNewWorkflow: () => false,
}));

vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowState: (selector: (state: unknown) => unknown) => {
    const state = { workflow: { id: 'workflow-1', lock_version: 1 } };
    return typeof selector === 'function' ? selector(state) : state;
  },
}));

vi.mock('../../../js/collaborative-editor/hooks/useUI', () => ({
  useIsRunPanelOpen: () => true,
  useUICommands: () => ({ closeRunPanel }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useHistory', () => ({
  useHistoryCommands: () => ({ closeRunViewer }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useVersionSelect', () => ({
  useVersionSelect: () => vi.fn(),
}));

function renderBreadcrumbs() {
  return render(
    <BreadcrumbContent
      workflowId="workflow-1"
      workflowName="Test Workflow"
      aiAssistantEnabled={false}
    />
  );
}

async function clickTitle() {
  await userEvent.click(screen.getByRole('button', { name: 'Test Workflow' }));
}

describe('workflow title breadcrumb', () => {
  beforeEach(() => {
    urlState.reset();
    closeRunPanel.mockClear();
    closeRunViewer.mockClear();
  });

  test('renders the workflow title as a button rather than plain text', () => {
    renderBreadcrumbs();

    expect(
      screen.getByRole('button', { name: 'Test Workflow' })
    ).toBeInTheDocument();
  });

  test('clicking the title returns to the bare canvas in a single update', async () => {
    urlState.setParams({
      panel: 'editor',
      job: 'job-1',
      run: 'run-1',
      step: 'step-1',
      runMode: 'custom-input',
    });

    renderBreadcrumbs();
    await clickTitle();

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledTimes(1);
    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      panel: null,
      job: null,
      trigger: null,
      edge: null,
      run: null,
      step: null,
      runMode: null,
    });
  });

  test('closes the run panel at the store, not only in the URL', async () => {
    // WorkflowEditor's sync effect rewrites panel=run while the store flag is
    // still set, so clearing the param alone would be undone immediately.
    urlState.setParams({ panel: 'run', job: 'job-1' });

    renderBreadcrumbs();
    await clickTitle();

    expect(closeRunPanel).toHaveBeenCalledTimes(1);
  });

  test('closes the run viewer at the store, not only in the URL', async () => {
    // CollaborativeWorkflowDiagram's restore effect rewrites run=<id> while a
    // run is active, so clearing the param alone would be undone immediately.
    urlState.setParams({ run: 'run-1', step: 'step-1' });

    renderBreadcrumbs();
    await clickTitle();

    expect(closeRunViewer).toHaveBeenCalledTimes(1);
  });
});
