/**
 * Workflow Title Breadcrumb Tests
 *
 * The workflow title in the editor breadcrumbs returns to the root workflow
 * editor view. Clicking it closes the full IDE (and any other panel),
 * deselects the current node, and drops any run-viewing context, landing on
 * the bare canvas.
 *
 * Breadcrumbs.test.tsx covers the BreadcrumbLink/BreadcrumbText primitives in
 * isolation. This file covers the wiring: that the title is rendered as a
 * button and that clicking it clears the right URL params in one update.
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
}));

vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowState: (selector: (state: unknown) => unknown) => {
    const state = { workflow: { id: 'workflow-1', lock_version: 1 } };
    return typeof selector === 'function' ? selector(state) : state;
  },
}));

vi.mock('../../../js/collaborative-editor/hooks/useUI', () => ({
  useIsRunPanelOpen: () => false,
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

describe('workflow title breadcrumb', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    urlState.reset();
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
      runMode: 'retry',
    });

    renderBreadcrumbs();

    await userEvent.click(
      screen.getByRole('button', { name: 'Test Workflow' })
    );

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

  test('clicking the title with the IDE open closes it', async () => {
    urlState.setParams({ panel: 'editor', job: 'job-1' });

    renderBreadcrumbs();

    await userEvent.click(
      screen.getByRole('button', { name: 'Test Workflow' })
    );

    const [update] = urlState.mockFns.updateSearchParams.mock.calls[0] as [
      Record<string, string | null>,
    ];
    expect(update['panel']).toBeNull();
    expect(update['job']).toBeNull();
  });
});
