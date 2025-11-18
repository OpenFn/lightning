/**
 * FullScreenIDE Docs/Metadata Panel Tests
 *
 * Tests for the nested docs/metadata panel within the center "Code" panel
 * of FullScreenIDE. This panel allows users to view adaptor documentation
 * and metadata alongside their code.
 *
 * Test coverage:
 * - Panel state management (collapsed/expanded via localStorage)
 * - Tab switching between Docs and Metadata
 * - Orientation toggle (horizontal/vertical layout)
 * - Integration with Code header buttons
 * - Panel resizing behavior
 * - LocalStorage persistence
 */

import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { HotkeysProvider } from 'react-hotkeys-hook';
import * as Y from 'yjs';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import { FullScreenIDE } from '../../../../js/collaborative-editor/components/ide/FullScreenIDE';
import * as dataclipApi from '../../../../js/collaborative-editor/api/dataclips';
import type { Workflow } from '../../../../js/collaborative-editor/types/workflow';
import { StoreProvider } from '#/collaborative-editor/contexts/StoreProvider';

// Mock dependencies
vi.mock('../../../../js/collaborative-editor/api/dataclips');

// Mock MonacoEditor
vi.mock('@monaco-editor/react', () => ({
  default: ({ value }: { value: string }) => (
    <div data-testid="monaco-editor">{value}</div>
  ),
}));

vi.mock('../../../../js/monaco', () => ({
  MonacoEditor: ({ value }: { value?: string }) => (
    <div data-testid="monaco-editor">{value}</div>
  ),
  setTheme: vi.fn(),
}));

// Mock tab panel components
vi.mock(
  '../../../../js/collaborative-editor/components/run-viewer/RunTabPanel',
  () => ({
    RunTabPanel: () => <div>Run Tab Content</div>,
  })
);

vi.mock(
  '../../../../js/collaborative-editor/components/run-viewer/LogTabPanel',
  () => ({
    LogTabPanel: () => <div>Log Tab Content</div>,
  })
);

vi.mock(
  '../../../../js/collaborative-editor/components/run-viewer/InputTabPanel',
  () => ({
    InputTabPanel: () => <div>Input Tab Content</div>,
  })
);

vi.mock(
  '../../../../js/collaborative-editor/components/run-viewer/OutputTabPanel',
  () => ({
    OutputTabPanel: () => <div>Output Tab Content</div>,
  })
);

// Mock CollaborativeMonaco
vi.mock(
  '../../../../js/collaborative-editor/components/CollaborativeMonaco',
  () => ({
    CollaborativeMonaco: () => (
      <div data-testid="collaborative-monaco">Monaco Editor</div>
    ),
  })
);

// Mock ManualRunPanel
vi.mock(
  '../../../../js/collaborative-editor/components/ManualRunPanel',
  () => ({
    ManualRunPanel: () => (
      <div data-testid="manual-run-panel">ManualRunPanel</div>
    ),
  })
);

// Mock Docs component
vi.mock('../../../../js/adaptor-docs/Docs', () => ({
  default: ({ adaptor }: { adaptor: string }) => (
    <div data-testid="docs-component">Docs for {adaptor}</div>
  ),
}));

// Mock Metadata component
vi.mock('../../../../js/metadata-explorer/Explorer', () => ({
  default: ({ adaptor, metadata }: { adaptor: string; metadata: any }) => (
    <div data-testid="metadata-component">
      Metadata for {adaptor}
      {metadata ? ` with data` : ' (no data)'}
    </div>
  ),
}));

// Mock useURLState hook
const mockSearchParams = new URLSearchParams();
mockSearchParams.set('job', 'job-1');

vi.mock('../../../../js/react/lib/use-url-state', () => ({
  useURLState: () => ({
    searchParams: mockSearchParams,
    updateSearchParams: vi.fn(),
    hash: '',
  }),
}));

// Mock session hooks
vi.mock('../../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: () => ({
    awareness: {
      setLocalStateField: vi.fn(),
      getStates: () => new Map(),
    },
  }),
}));

vi.mock('../../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useProject: () => ({
    id: 'project-1',
    name: 'Test Project',
  }),
  useProjectRepoConnection: () => undefined,
  useLatestSnapshotLockVersion: () => 1,
  useIsNewWorkflow: () => false,
  useUser: () => ({
    id: 'user-1',
    first_name: 'Test',
    last_name: 'User',
    email: 'test@example.com',
  }),
  useAppConfig: () => ({
    ai_enabled: false,
  }),
}));

// Mock workflow hooks
const mockWorkflow: Workflow = {
  id: 'workflow-1',
  name: 'Test Workflow',
  jobs: [
    {
      id: 'job-1',
      name: 'Test Job',
      adaptor: '@openfn/language-http@2.0.0',
      body: 'fn(state => state)',
      enabled: true,
      project_credential_id: null,
      keychain_credential_id: null,
    },
  ],
  triggers: [
    {
      id: 'trigger-1',
      type: 'webhook',
      enabled: true,
    },
  ],
  edges: [],
};

const mockYText = new Y.Text();
mockYText.insert(0, 'fn(state => state)');

vi.mock('../../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useCanSave: () => ({
    canSave: true,
    tooltipMessage: 'Save workflow',
  }),
  useCanRun: () => ({
    canRun: true,
    tooltipMessage: 'Run workflow',
  }),
  useWorkflowReadOnly: () => ({
    isReadOnly: false,
    tooltipMessage: '',
  }),
  useWorkflowSettingsErrors: () => ({
    hasErrors: false,
    errors: [],
  }),
  useCurrentJob: () => ({
    job: {
      id: 'job-1',
      name: 'Test Job',
      adaptor: '@openfn/language-http@2.0.0',
      body: 'fn(state => state)',
      project_credential_id: null,
      keychain_credential_id: null,
    },
    ytext: mockYText,
  }),
  useNodeSelection: () => ({
    currentNode: { node: null, type: null, id: null },
    selectNode: vi.fn(),
  }),
  useWorkflowEnabled: () => ({
    enabled: true,
    setEnabled: vi.fn(),
  }),
  useWorkflowActions: () => ({
    selectJob: vi.fn(),
    saveWorkflow: vi.fn(),
    updateJob: vi.fn(),
  }),
  useWorkflowState: (selector: any) => {
    const state = {
      workflow: mockWorkflow,
      jobs: mockWorkflow.jobs,
      triggers: mockWorkflow.triggers,
      edges: mockWorkflow.edges,
      positions: {},
    };
    return typeof selector === 'function' ? selector(state) : state;
  },
}));

// Mock useRun hooks
vi.mock('../../../../js/collaborative-editor/hooks/useRun', () => ({
  useRunStoreInstance: () => ({
    getState: vi.fn(() => ({
      run: null,
      loading: false,
      error: null,
    })),
    subscribe: vi.fn(),
    setState: vi.fn(),
    _connectToRun: vi.fn(() => vi.fn()),
    _disconnectFromRun: vi.fn(),
  }),
  useRunActions: () => ({
    selectStep: vi.fn(),
  }),
  useCurrentRun: () => null,
}));

// Mock credential hooks
vi.mock('../../../../js/collaborative-editor/hooks/useCredentials', () => ({
  useCredentials: () => ({
    projectCredentials: [],
    keychainCredentials: [],
  }),
  useCredentialsCommands: () => ({
    requestCredentials: vi.fn(),
  }),
}));

// Mock adaptor hooks
vi.mock('../../../../js/collaborative-editor/hooks/useAdaptors', () => ({
  useProjectAdaptors: () => ({
    projectAdaptors: [],
    allAdaptors: [],
  }),
}));

// Mock LiveView actions
vi.mock(
  '../../../../js/collaborative-editor/contexts/LiveViewActionsContext',
  () => ({
    useLiveViewActions: () => ({
      pushEvent: vi.fn(),
      handleEvent: vi.fn(() => () => {}),
    }),
  })
);

// Mock adaptor modals
vi.mock(
  '../../../../js/collaborative-editor/components/ConfigureAdaptorModal',
  () => ({
    ConfigureAdaptorModal: () => <div data-testid="configure-adaptor-modal" />,
  })
);

vi.mock(
  '../../../../js/collaborative-editor/components/AdaptorSelectionModal',
  () => ({
    AdaptorSelectionModal: () => <div data-testid="adaptor-selection-modal" />,
  })
);

// Mock useRunRetry hook
vi.mock('../../../../js/collaborative-editor/hooks/useRunRetry', () => ({
  useRunRetry: () => ({
    handleRun: vi.fn(),
    handleRetry: vi.fn(),
    isSubmitting: false,
    isRetryable: false,
    runIsProcessing: false,
    canRun: true,
  }),
}));

// Mock UI commands
vi.mock('../../../../js/collaborative-editor/hooks/useUI', () => ({
  useUICommands: () => ({
    openGitHubSyncModal: vi.fn(),
    openRunPanel: vi.fn(),
    closeRunPanel: vi.fn(),
  }),
  useIsRunPanelOpen: () => false,
  useIsGitHubSyncModalOpen: () => false,
  useRunPanelContext: () => null,
}));

// Mock GitHubSyncModal
vi.mock(
  '../../../../js/collaborative-editor/components/GitHubSyncModal',
  () => ({
    GitHubSyncModal: () => null,
  })
);

// Mock react-resizable-panels with ref support
vi.mock('react-resizable-panels', async () => {
  const React = await import('react');

  const Panel = React.forwardRef(
    (
      {
        children,
        onCollapse,
        onExpand,
        defaultSize,
        collapsible,
        collapsedSize,
      }: any,
      ref: any
    ) => {
      // Create imperative handle methods
      React.useImperativeHandle(ref, () => ({
        collapse: () => {
          if (onCollapse) onCollapse();
        },
        expand: () => {
          if (onExpand) onExpand();
        },
        isCollapsed: () => false,
      }));

      return (
        <div
          data-testid="panel"
          data-default-size={defaultSize}
          data-collapsed="false"
        >
          {children}
        </div>
      );
    }
  );

  return {
    Panel,
    PanelGroup: ({ children, direction }: any) => (
      <div data-testid="panel-group" data-direction={direction}>
        {children}
      </div>
    ),
    PanelResizeHandle: ({ className }: any) => (
      <div data-testid="resize-handle" className={className} />
    ),
  };
});

// Helper function to render FullScreenIDE
function renderFullScreenIDE(
  props: React.ComponentProps<typeof FullScreenIDE>
) {
  return render(
    <HotkeysProvider>
      <StoreProvider>
        <FullScreenIDE {...props} />
      </StoreProvider>
    </HotkeysProvider>
  );
}

describe('FullScreenIDE - Docs/Metadata Panel', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();

    // Default mock for searchDataclips
    vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
      data: [],
      next_cron_run_dataclip_id: null,
      can_edit_dataclip: true,
    });

    // Reset search params
    mockSearchParams.delete('job');
    mockSearchParams.set('job', 'job-1');
  });

  describe('panel state management', () => {
    test('panel starts expanded by default when no localStorage value', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument();
      });

      // Docs tab and content should be visible (look for pill tab which has rounded-md class)
      const docsTabs = screen.getAllByRole('button', { name: /^Docs$/i });
      const docsPillTab = docsTabs.find(btn =>
        btn.className.includes('rounded-md')
      );
      expect(docsPillTab).toBeInTheDocument();

      // Should render Docs component by default
      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });
    });

    test('panel starts collapsed when localStorage says collapsed=true', async () => {
      localStorage.setItem(
        'lightning.ide.docsPanel.collapsed',
        JSON.stringify(true)
      );

      const onClose = vi.fn();
      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument();
      });

      // Panel content should not be visible when collapsed
      expect(screen.queryByTestId('docs-component')).not.toBeInTheDocument();
      expect(
        screen.queryByTestId('metadata-component')
      ).not.toBeInTheDocument();
    });

    test('panel collapse persists to localStorage', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });

      // Find and click the X button to close the panel
      const closeButton = screen.getByRole('button', {
        name: /close docs panel/i,
      });
      await user.click(closeButton);

      // Wait for state update
      await waitFor(() => {
        expect(localStorage.getItem('lightning.ide.docsPanel.collapsed')).toBe(
          'true'
        );
      });
    });

    test('clicking Docs button in header opens collapsed panel', async () => {
      const user = userEvent.setup();
      localStorage.setItem(
        'lightning.ide.docsPanel.collapsed',
        JSON.stringify(true)
      );

      const onClose = vi.fn();
      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument();
      });

      // Initially collapsed - no docs visible
      expect(screen.queryByTestId('docs-component')).not.toBeInTheDocument();

      // Find and click the Docs button in header (look for button with "Docs" text in Code header area)
      const docsHeaderButtons = screen.getAllByRole('button', {
        name: /^Docs$/i,
      });
      // The header button is the one with the smaller text (not the pill tab)
      const docsHeaderButton = docsHeaderButtons.find(
        btn =>
          btn.className.includes('text-xs') && btn.className.includes('gap-1')
      );

      await user.click(docsHeaderButton);

      // Panel should expand and show docs
      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });
    });

    test('clicking Metadata button in header opens collapsed panel with metadata tab', async () => {
      const user = userEvent.setup();
      localStorage.setItem(
        'lightning.ide.docsPanel.collapsed',
        JSON.stringify(true)
      );

      const onClose = vi.fn();
      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument();
      });

      // Find and click the Metadata button in header
      const metadataHeaderButtons = screen.getAllByRole('button', {
        name: /^Metadata$/i,
      });
      const metadataHeaderButton = metadataHeaderButtons.find(
        btn =>
          btn.className.includes('text-xs') && btn.className.includes('gap-1')
      );

      await user.click(metadataHeaderButton);

      // Panel should expand and show metadata
      await waitFor(() => {
        expect(screen.getByTestId('metadata-component')).toBeInTheDocument();
      });
    });
  });

  describe('tab switching', () => {
    test('Docs tab is selected by default', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });

      // Should render Docs component with correct adaptor
      expect(
        screen.getByText(/Docs for @openfn\/language-http@2\.0\.0/i)
      ).toBeInTheDocument();
    });

    test('user can switch to Metadata tab using pills tabs', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });

      // Find the Metadata pill tab (inside the panel, not header)
      const docsPanelTabs = screen.getAllByRole('button', {
        name: /^Metadata$/i,
      });
      // The pill tab should be the one with the filled style
      const metadataTab = docsPanelTabs.find(btn =>
        btn.className.includes('rounded-md')
      );

      expect(metadataTab).toBeInTheDocument();
      await user.click(metadataTab!);

      // Should switch to Metadata component
      await waitFor(() => {
        expect(screen.getByTestId('metadata-component')).toBeInTheDocument();
      });

      // Verify metadata component shows correct adaptor
      expect(
        screen.getByText(/Metadata for @openfn\/language-http@2\.0\.0/i)
      ).toBeInTheDocument();
    });

    test('selected tab persists when panel is collapsed and expanded', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });

      // Switch to Metadata tab
      const metadataTab = screen
        .getAllByRole('button', { name: /^Metadata$/i })
        .find(btn => btn.className.includes('rounded-md'));
      await user.click(metadataTab!);

      await waitFor(() => {
        expect(screen.getByTestId('metadata-component')).toBeInTheDocument();
      });

      // Close the panel
      const closeButton = screen.getByRole('button', {
        name: /close docs panel/i,
      });
      await user.click(closeButton);

      await waitFor(() => {
        expect(
          screen.queryByTestId('metadata-component')
        ).not.toBeInTheDocument();
      });

      // Reopen via header button
      const metadataHeaderButtons = screen.getAllByRole('button', {
        name: /^Metadata$/i,
      });
      const metadataHeaderButton = metadataHeaderButtons.find(
        btn =>
          btn.className.includes('text-xs') && btn.className.includes('gap-1')
      );
      await user.click(metadataHeaderButton!);

      // Should still show Metadata tab
      await waitFor(() => {
        expect(screen.getByTestId('metadata-component')).toBeInTheDocument();
      });
    });

    test('correct content is shown for each tab', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });

      // Docs component should be shown with correct adaptor
      expect(
        screen.getByText(/Docs for @openfn\/language-http@2\.0\.0/i)
      ).toBeInTheDocument();

      // Switch to Metadata
      const metadataTab = screen
        .getAllByRole('button', { name: /^Metadata$/i })
        .find(btn => btn.className.includes('rounded-md'));
      await user.click(metadataTab!);

      await waitFor(() => {
        expect(screen.getByTestId('metadata-component')).toBeInTheDocument();
      });

      // Metadata component should be shown with correct adaptor and null metadata
      expect(
        screen.getByText(/Metadata for @openfn\/language-http@2\.0\.0/i)
      ).toBeInTheDocument();
      expect(screen.getByText(/\(no data\)/i)).toBeInTheDocument();
    });
  });

  describe('orientation toggle', () => {
    test('panel defaults to horizontal orientation', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });

      // Find the nested PanelGroup inside the center panel
      const panelGroups = screen.getAllByTestId('panel-group');
      // The nested one should have direction="horizontal"
      const nestedPanelGroup = panelGroups.find(
        group => group.getAttribute('data-direction') === 'horizontal'
      );

      expect(nestedPanelGroup).toBeInTheDocument();
    });

    test('user can toggle to vertical orientation', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });

      // Find and click the orientation toggle button
      const toggleButton = screen.getByRole('button', {
        name: /toggle panel orientation/i,
      });
      await user.click(toggleButton);

      // Check localStorage was updated
      await waitFor(() => {
        expect(
          localStorage.getItem('lightning.ide.docsPanel.orientation')
        ).toBe('vertical');
      });
    });

    test('orientation persists to localStorage', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });

      // Toggle to vertical
      const toggleButton = screen.getByRole('button', {
        name: /toggle panel orientation/i,
      });
      await user.click(toggleButton);

      await waitFor(() => {
        expect(
          localStorage.getItem('lightning.ide.docsPanel.orientation')
        ).toBe('vertical');
      });

      // Wait for re-render with new PanelGroup direction
      await waitFor(() => {
        const panelGroups = screen.getAllByTestId('panel-group');
        const nestedPanelGroup = panelGroups.find(
          group => group.getAttribute('data-direction') === 'vertical'
        );
        expect(nestedPanelGroup).toBeInTheDocument();
      });

      // Get fresh reference to toggle button after re-render
      const toggleButtonAfterFirstToggle = screen.getByRole('button', {
        name: /toggle panel orientation/i,
      });

      // Toggle back to horizontal
      await user.click(toggleButtonAfterFirstToggle);

      await waitFor(() => {
        expect(
          localStorage.getItem('lightning.ide.docsPanel.orientation')
        ).toBe('horizontal');
      });
    });

    test('loads orientation from localStorage on mount', async () => {
      localStorage.setItem('lightning.ide.docsPanel.orientation', 'vertical');

      const onClose = vi.fn();
      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });

      // Should render with vertical orientation
      const panelGroups = screen.getAllByTestId('panel-group');
      const nestedPanelGroup = panelGroups.find(
        group => group.getAttribute('data-direction') === 'vertical'
      );

      expect(nestedPanelGroup).toBeInTheDocument();
    });

    test('resize handle updates based on orientation', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });

      // Initially horizontal - should have cursor-col-resize
      const resizeHandles = screen.getAllByTestId('resize-handle');
      const docsResizeHandle = resizeHandles.find(handle =>
        handle.className.includes('cursor-col-resize')
      );
      expect(docsResizeHandle).toBeInTheDocument();

      // Toggle to vertical
      const toggleButton = screen.getByRole('button', {
        name: /toggle panel orientation/i,
      });
      await user.click(toggleButton);

      // After toggle, should have cursor-row-resize
      await waitFor(() => {
        const updatedHandles = screen.getAllByTestId('resize-handle');
        const verticalHandle = updatedHandles.find(handle =>
          handle.className.includes('cursor-row-resize')
        );
        expect(verticalHandle).toBeInTheDocument();
      });
    });
  });

  describe('integration with Code header', () => {
    test('Docs button highlights when docs tab is active and panel is open', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });

      // Find Docs button in header
      const docsHeaderButtons = screen.getAllByRole('button', {
        name: /^Docs$/i,
      });
      const docsHeaderButton = docsHeaderButtons.find(
        btn =>
          btn.className.includes('text-xs') && btn.className.includes('gap-1')
      )!;

      // Should have primary highlight classes when active
      expect(docsHeaderButton.className).toContain('bg-primary-100');
      expect(docsHeaderButton.className).toContain('text-primary-800');
    });

    test('Metadata button highlights when metadata tab is active and panel is open', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });

      // Switch to Metadata tab
      const metadataTab = screen
        .getAllByRole('button', { name: /^Metadata$/i })
        .find(btn => btn.className.includes('rounded-md'));
      await user.click(metadataTab!);

      await waitFor(() => {
        expect(screen.getByTestId('metadata-component')).toBeInTheDocument();
      });

      // Find Metadata button in header
      const metadataHeaderButtons = screen.getAllByRole('button', {
        name: /^Metadata$/i,
      });
      const metadataHeaderButton = metadataHeaderButtons.find(
        btn =>
          btn.className.includes('text-xs') && btn.className.includes('gap-1')
      )!;

      // Should have primary highlight classes when active
      expect(metadataHeaderButton.className).toContain('bg-primary-100');
      expect(metadataHeaderButton.className).toContain('text-primary-800');
    });

    test('header buttons do not highlight when panel is collapsed', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });

      // Close the panel
      const closeButton = screen.getByRole('button', {
        name: /close docs panel/i,
      });
      await user.click(closeButton);

      await waitFor(() => {
        expect(screen.queryByTestId('docs-component')).not.toBeInTheDocument();
      });

      // Header buttons should not have highlight classes
      const docsHeaderButtons = screen.getAllByRole('button', {
        name: /^Docs$/i,
      });
      const docsHeaderButton = docsHeaderButtons.find(
        btn =>
          btn.className.includes('text-xs') && btn.className.includes('gap-1')
      )!;

      expect(docsHeaderButton.className).not.toContain('bg-primary-100');
      expect(docsHeaderButton.className).toContain('text-gray-400');
    });

    test('clicking Docs header button switches to docs tab if panel is open with metadata', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });

      // Switch to Metadata tab
      const metadataTab = screen
        .getAllByRole('button', { name: /^Metadata$/i })
        .find(btn => btn.className.includes('rounded-md'));
      await user.click(metadataTab!);

      await waitFor(() => {
        expect(screen.getByTestId('metadata-component')).toBeInTheDocument();
      });

      // Click Docs button in header
      const docsHeaderButtons = screen.getAllByRole('button', {
        name: /^Docs$/i,
      });
      const docsHeaderButton = docsHeaderButtons.find(
        btn =>
          btn.className.includes('text-xs') && btn.className.includes('gap-1')
      )!;
      await user.click(docsHeaderButton);

      // Should switch back to Docs tab
      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });
    });
  });

  describe('panel resizing', () => {
    test('panel is resizable with visible resize handle', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });

      // Should have resize handles
      const resizeHandles = screen.getAllByTestId('resize-handle');
      expect(resizeHandles.length).toBeGreaterThan(0);

      // At least one should be for the docs panel (with col-resize cursor)
      const docsResizeHandle = resizeHandles.find(handle =>
        handle.className.includes('cursor-col-resize')
      );
      expect(docsResizeHandle).toBeInTheDocument();
    });

    test('resize handle has correct cursor based on orientation', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });

      // Initially horizontal - should have col-resize
      let resizeHandles = screen.getAllByTestId('resize-handle');
      let docsResizeHandle = resizeHandles.find(handle =>
        handle.className.includes('cursor-col-resize')
      );
      expect(docsResizeHandle).toBeInTheDocument();

      // Toggle to vertical
      const toggleButton = screen.getByRole('button', {
        name: /toggle panel orientation/i,
      });
      await user.click(toggleButton);

      // Should now have row-resize
      await waitFor(() => {
        resizeHandles = screen.getAllByTestId('resize-handle');
        const verticalHandle = resizeHandles.find(handle =>
          handle.className.includes('cursor-row-resize')
        );
        expect(verticalHandle).toBeInTheDocument();
      });
    });
  });

  describe('accessibility', () => {
    test('close button has proper aria-label', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });

      const closeButton = screen.getByRole('button', {
        name: /close docs panel/i,
      });
      expect(closeButton).toHaveAttribute('aria-label', 'Close docs panel');
    });

    test('orientation toggle button has proper title', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('docs-component')).toBeInTheDocument();
      });

      const toggleButton = screen.getByRole('button', {
        name: /toggle panel orientation/i,
      });
      expect(toggleButton).toHaveAttribute('title', 'Toggle panel orientation');
    });

    test('header buttons have descriptive titles', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument();
      });

      const docsButtons = screen.getAllByRole('button', { name: /^Docs$/i });
      const docsButton = docsButtons.find(
        btn =>
          btn.className.includes('text-xs') && btn.className.includes('gap-1')
      )!;
      expect(docsButton).toHaveAttribute('title', 'Show adaptor documentation');

      const metadataButtons = screen.getAllByRole('button', {
        name: /^Metadata$/i,
      });
      const metadataButton = metadataButtons.find(
        btn =>
          btn.className.includes('text-xs') && btn.className.includes('gap-1')
      )!;
      expect(metadataButton).toHaveAttribute('title', 'Show metadata explorer');
    });
  });
});
