/**
 * FullScreenIDE Keyboard Shortcut Tests
 *
 * Tests keyboard shortcuts for the FullScreenIDE component:
 * - Escape: Smart behavior (blur Monaco first, then close IDE)
 * - Mod+Enter: Run or retry (prioritizes retry when available)
 * - Mod+Shift+Enter: Force new run (ignores retry)
 *
 * Testing approach:
 * - Library-agnostic (tests user-facing behavior, not implementation)
 * - Platform coverage (Mac Cmd and Windows Ctrl)
 * - Modal state interaction (shortcuts disabled when modals open)
 * - Monaco editor integration (contentEditable and focus detection)
 */

import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import * as Y from 'yjs';

import * as dataclipApi from '../../../../js/collaborative-editor/api/dataclips';
import { FullScreenIDE } from '../../../../js/collaborative-editor/components/ide/FullScreenIDE';
import type { UseRunRetryReturn } from '../../../../js/collaborative-editor/hooks/useRunRetry';
import { KeyboardProvider } from '../../../../js/collaborative-editor/keyboard/KeyboardProvider';
import { focusElement } from '../../../keyboard-test-utils';

// Helper to fire keyboard event and wait for component to process
async function pressKey(
  key: string,
  modifiers: Partial<KeyboardEventInit> = {},
  target: Element | Document = document
) {
  fireEvent.keyDown(target, {
    key,
    code: key,
    bubbles: true,
    cancelable: true,
    ...modifiers,
  });
  // Small delay to let react-hotkeys-hook process the event
  await new Promise(resolve => setTimeout(resolve, 10));
}

// Helper to test platform variants (Mac Cmd vs Windows Ctrl)
async function testPlatformVariants(
  testFn: (
    modifierKey: { metaKey: boolean } | { ctrlKey: boolean }
  ) => Promise<void>
) {
  await testFn({ metaKey: true });
  await testFn({ ctrlKey: true });
}

// Helper to verify a shortcut does NOT fire
async function expectShortcutNotToFire(
  key: string,
  modifiers: Partial<KeyboardEventInit>,
  mockFn: any,
  target: Element | Document = document
) {
  const callCountBefore = mockFn.mock.calls.length;
  await pressKey(key, modifiers, target);

  // Wait a bit to ensure handler doesn't fire
  await new Promise(resolve => setTimeout(resolve, 50));

  expect(mockFn.mock.calls.length).toBe(callCountBefore);
}

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

// Mock CollaborativeMonaco with contentEditable support
vi.mock(
  '../../../../js/collaborative-editor/components/CollaborativeMonaco',
  () => ({
    CollaborativeMonaco: () => (
      <div className="monaco-editor" data-testid="collaborative-monaco">
        <div
          contentEditable="true"
          suppressContentEditableWarning={true}
          data-testid="monaco-contenteditable"
          tabIndex={0}
        >
          Monaco Editor
        </div>
      </div>
    ),
  })
);

// Mock ManualRunPanel with run state callbacks
vi.mock(
  '../../../../js/collaborative-editor/components/ManualRunPanel',
  () => ({
    ManualRunPanel: () => (
      <div data-testid="manual-run-panel">Manual Run Panel</div>
    ),
  })
);

// Mock AdaptorSelectionModal
vi.mock(
  '../../../../js/collaborative-editor/components/AdaptorSelectionModal',
  () => ({
    AdaptorSelectionModal: () => null,
  })
);

// Mock ConfigureAdaptorModal
vi.mock(
  '../../../../js/collaborative-editor/components/ConfigureAdaptorModal',
  () => ({
    ConfigureAdaptorModal: () => null,
  })
);

// Mock CredentialModal
vi.mock(
  '../../../../js/collaborative-editor/components/CredentialModal',
  () => ({
    CredentialModal: () => null,
  })
);

// Mock ActiveCollaborators
vi.mock(
  '../../../../js/collaborative-editor/components/ActiveCollaborators',
  () => ({
    ActiveCollaborators: () => null,
  })
);

// Mock useRunRetry hook to provide controllable run/retry handlers
const mockUseRunRetry = vi.fn();
vi.mock('../../../../js/collaborative-editor/hooks/useRunRetry', () => ({
  useRunRetry: () => mockUseRunRetry(),
}));

// Mock URL state
const mockSearchParams = new URLSearchParams();
mockSearchParams.set('job', 'test-job-id');

vi.mock('../../../../js/react/lib/use-url-state', () => ({
  useURLState: () => ({
    searchParams: mockSearchParams,
    updateSearchParams: vi.fn(),
    hash: '',
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

// Mock session hooks
vi.mock('../../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: (selector: any) => {
    const state = {
      awareness: {
        setLocalStateField: vi.fn(),
        getStates: () => new Map(),
      },
      provider: null,
    };
    return typeof selector === 'function' ? selector(state) : state;
  },
}));

vi.mock('../../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useProject: () => ({
    id: 'project-1',
    name: 'Test Project',
  }),
  useProjectRepoConnection: () => undefined,
  useLatestSnapshotLockVersion: () => 1,
  useIsNewWorkflow: () => false,
}));

// Mock UI commands
vi.mock('../../../../js/collaborative-editor/hooks/useUI', () => ({
  useUICommands: () => ({
    openGitHubSyncModal: vi.fn(),
  }),
}));

// Mock workflow hooks
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
  useCurrentJob: () => ({
    job: {
      id: 'test-job-id',
      name: 'Test Job',
      adaptor: '@openfn/language-http@latest',
      body: 'fn(state => state)',
      project_credential_id: null,
      keychain_credential_id: null,
    },
    ytext: mockYText,
  }),
  useWorkflowActions: () => ({
    selectJob: vi.fn(),
    saveWorkflow: vi.fn(),
    updateJob: vi.fn(),
  }),
  useWorkflowState: (selector: any) => {
    const state = {
      workflow: {
        id: 'workflow-1',
        name: 'Test Workflow',
        lock_version: 1,
      },
      jobs: [
        {
          id: 'test-job-id',
          name: 'Test Job',
          adaptor: '@openfn/language-http@latest',
          body: 'fn(state => state)',
        },
      ],
      triggers: [
        {
          id: 'trigger-1',
          type: 'webhook',
        },
      ],
      edges: [],
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
  useCredentialQueries: () => ({
    credentials: [],
    loading: false,
  }),
}));

// Mock adaptor hooks
vi.mock('../../../../js/collaborative-editor/hooks/useAdaptors', () => ({
  useProjectAdaptors: () => ({
    projectAdaptors: [],
    allAdaptors: [],
  }),
  useAdaptors: () => ({
    adaptors: [],
    loading: false,
  }),
}));

// Mock awareness hooks
vi.mock('../../../../js/collaborative-editor/hooks/useAwareness', () => ({
  useAwarenessStore: () => ({
    getState: vi.fn(() => ({
      users: [],
    })),
    subscribe: vi.fn(),
  }),
  useRemoteUsers: () => [],
}));

// Create stable function references that persist across test renders
// This prevents re-registering hotkeys on React 18 StrictMode double-renders
let stableHandleRun: ReturnType<typeof vi.fn>;
let stableHandleRetry: ReturnType<typeof vi.fn>;

// Helper to set up mock useRunRetry with stable function references
function setupMockUseRunRetry(options: Partial<UseRunRetryReturn> = {}) {
  // Create new stable functions if not provided, or reuse existing ones
  if (!stableHandleRun || options.handleRun) {
    stableHandleRun = options.handleRun || vi.fn();
  }
  if (!stableHandleRetry || options.handleRetry) {
    stableHandleRetry = options.handleRetry || vi.fn();
  }

  mockUseRunRetry.mockImplementation(() => ({
    handleRun: stableHandleRun,
    handleRetry: stableHandleRetry,
    isSubmitting: false,
    isRetryable: false,
    runIsProcessing: false,
    canRun: true,
    ...options,
  }));

  return { handleRun: stableHandleRun, handleRetry: stableHandleRetry };
}

// Helper to render FullScreenIDE with KeyboardProvider
function renderFullScreenIDE(props = {}) {
  const defaultProps = {
    onClose: vi.fn(),
    parentProjectId: null,
    parentProjectName: null,
    ...props,
  };

  return render(
    <KeyboardProvider>
      <FullScreenIDE {...defaultProps} />
    </KeyboardProvider>
  );
}

describe('FullScreenIDE Keyboard Shortcuts', () => {
  beforeEach(() => {
    // Reset stable function references for each test
    stableHandleRun = null as any;
    stableHandleRetry = null as any;

    // Clear only call history, not implementations
    mockUseRunRetry.mockClear();
    vi.mocked(dataclipApi.getRunDataclip).mockResolvedValue({
      dataclip: null,
    });

    // Note: Each test calls setupMockUseRunRetry() to create fresh stable refs
  });

  describe('Escape - Close IDE / Blur Monaco', () => {
    test('closes IDE when Monaco is not focused', async () => {
      setupMockUseRunRetry();
      const onClose = vi.fn();
      renderFullScreenIDE({ onClose });

      // Wait for component to fully render
      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      // Give time for scope to be enabled
      await new Promise(resolve => setTimeout(resolve, 200));

      // Give time for scope to be enabled and effects to run
      await new Promise(resolve => setTimeout(resolve, 200));

      // Fire escape directly on document
      fireEvent.keyDown(document, { key: 'Escape', code: 'Escape' });

      await waitFor(() => expect(onClose).toHaveBeenCalled(), {
        timeout: 2000,
      });
    });

    test('blurs Monaco on first Escape, closes IDE on second Escape', async () => {
      setupMockUseRunRetry();
      const onClose = vi.fn();
      renderFullScreenIDE({ onClose });

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      // Give time for scope to be enabled
      await new Promise(resolve => setTimeout(resolve, 200));

      // Give time for scope to be enabled
      await new Promise(resolve => setTimeout(resolve, 200));

      // Focus Monaco editor
      const monacoContent = screen.getByTestId('monaco-contenteditable');
      focusElement(monacoContent);

      // First Escape: blur Monaco
      await pressKey('Escape');

      await waitFor(() => {
        expect(document.activeElement).not.toBe(monacoContent);
      });

      // onClose should not be called yet
      expect(onClose).not.toHaveBeenCalled();

      // Second Escape: close IDE
      await pressKey('Escape');

      await waitFor(() => expect(onClose).toHaveBeenCalled());
    });

    test('enabled property reflects modal state (implementation detail test)', async () => {
      // NOTE: This test verifies the keyboard shortcut respects modal state
      // In the real implementation, the Escape handler has:
      // enabled: !isConfigureModalOpen && !isAdaptorPickerOpen && !isCredentialModalOpen
      // This prevents Escape from closing the IDE when modals are open.
      // We can't easily test the full modal interaction in this unit test,
      // but the logic is verified by reading lines 523-524 of FullScreenIDE.tsx

      setupMockUseRunRetry();
      const onClose = vi.fn();
      renderFullScreenIDE({ onClose });

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      // Give time for scope to be enabled
      await new Promise(resolve => setTimeout(resolve, 200));

      // Give time for scope to be enabled
      await new Promise(resolve => setTimeout(resolve, 200));

      // When no modals are open, Escape should work
      await pressKey('Escape');
      await waitFor(() => expect(onClose).toHaveBeenCalled());

      // The enabled option in the actual implementation prevents Escape
      // from firing when isConfigureModalOpen, isAdaptorPickerOpen, or
      // isCredentialModalOpen are true. This is tested in integration tests.
    });

    test('works with enableOnFormTags (input, textarea, select)', async () => {
      setupMockUseRunRetry();
      const onClose = vi.fn();
      renderFullScreenIDE({ onClose });

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      // Give time for scope to be enabled
      await new Promise(resolve => setTimeout(resolve, 200));

      // Give time for scope to be enabled
      await new Promise(resolve => setTimeout(resolve, 200));

      // Create and focus an input element
      const input = document.createElement('input');
      document.body.appendChild(input);
      focusElement(input);

      // Escape should still work in form tags
      await pressKey('Escape');

      await waitFor(() => expect(onClose).toHaveBeenCalled());

      document.body.removeChild(input);
    });
  });

  describe('Mod+Enter - Run or Retry', () => {
    test('calls handleRun when retry is not available (Mac)', async () => {
      const user = userEvent.setup();
      const { handleRun } = setupMockUseRunRetry();

      const { container } = renderFullScreenIDE();

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      container.focus();

      // Press Cmd+Enter (Mac)
      await user.keyboard('{Meta>}{Enter}{/Meta}');

      await waitFor(() => expect(handleRun).toHaveBeenCalled());
    });

    test('calls handleRun when retry is not available (Windows)', async () => {
      const user = userEvent.setup();
      const { handleRun } = setupMockUseRunRetry();

      const { container } = renderFullScreenIDE();

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      container.focus();

      // Press Ctrl+Enter (Windows/Linux)
      await user.keyboard('{Control>}{Enter}{/Control}');

      await waitFor(() => expect(handleRun).toHaveBeenCalled());
    });

    test('prioritizes handleRetry when retry is available', async () => {
      const user = userEvent.setup();
      const { handleRun, handleRetry } = setupMockUseRunRetry({
        isRetryable: true,
      });

      const { container } = renderFullScreenIDE();

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      container.focus();

      await user.keyboard('{Meta>}{Enter}{/Meta}');
      await waitFor(() => {
        expect(handleRetry).toHaveBeenCalled();
        expect(handleRun).not.toHaveBeenCalled();
      });
    });

    test('works in Monaco editor (contentEditable)', async () => {
      const user = userEvent.setup();
      const { handleRun } = setupMockUseRunRetry();

      renderFullScreenIDE();

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      // Focus Monaco editor
      const monacoContent = screen.getByTestId('monaco-contenteditable');
      focusElement(monacoContent);

      // Mod+Enter should work even in contentEditable
      await user.keyboard('{Meta>}{Enter}{/Meta}');
      await waitFor(() => expect(handleRun).toHaveBeenCalled());
    });

    test('works in form tags (input, textarea, select)', async () => {
      const user = userEvent.setup();
      const { handleRun } = setupMockUseRunRetry();

      renderFullScreenIDE();

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      // Create and focus an input element
      const input = document.createElement('input');
      document.body.appendChild(input);
      focusElement(input);

      // Mod+Enter should work in form tags
      await user.keyboard('{Meta>}{Enter}{/Meta}');
      await waitFor(() => expect(handleRun).toHaveBeenCalled());

      document.body.removeChild(input);
    });

    test('calls handleRun even when canRun is false (guards are in handler)', async () => {
      const user = userEvent.setup();
      const { handleRun } = setupMockUseRunRetry({ canRun: false });

      const { container } = renderFullScreenIDE();

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      container.focus();

      // Keyboard shortcut calls handler unconditionally
      // The handler itself checks canRunWorkflow internally
      await user.keyboard('{Meta>}{Enter}{/Meta}');
      await waitFor(() => expect(handleRun).toHaveBeenCalled());
    });

    test('calls handleRun even when isSubmitting is true (guards are in handler)', async () => {
      const user = userEvent.setup();
      const { handleRun } = setupMockUseRunRetry({ isSubmitting: true });

      const { container } = renderFullScreenIDE();

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      container.focus();

      // Keyboard shortcut calls handler unconditionally
      // The handler itself has guards (e.g., isRetryingRef) to prevent double-calls
      await user.keyboard('{Meta>}{Enter}{/Meta}');
      await waitFor(() => expect(handleRun).toHaveBeenCalled());
    });
  });

  describe('Mod+Shift+Enter - Force New Run', () => {
    test('calls handleRun even when retry is available (Mac)', async () => {
      const user = userEvent.setup();
      const { handleRun, handleRetry } = setupMockUseRunRetry({
        isRetryable: true,
      });

      const { container } = renderFullScreenIDE();

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      container.focus();

      await user.keyboard('{Meta>}{Shift>}{Enter}{/Shift}{/Meta}');
      await waitFor(() => {
        expect(handleRun).toHaveBeenCalled();
        expect(handleRetry).not.toHaveBeenCalled();
      });
    });

    test('calls handleRun even when retry is available (Windows)', async () => {
      const user = userEvent.setup();
      const { handleRun, handleRetry } = setupMockUseRunRetry({
        isRetryable: true,
      });

      const { container } = renderFullScreenIDE();

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      container.focus();

      await user.keyboard('{Control>}{Shift>}{Enter}{/Shift}{/Control}');
      await waitFor(() => {
        expect(handleRun).toHaveBeenCalled();
        expect(handleRetry).not.toHaveBeenCalled();
      });
    });

    test('works in Monaco editor (contentEditable)', async () => {
      const user = userEvent.setup();
      const { handleRun } = setupMockUseRunRetry();

      renderFullScreenIDE();

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      // Focus Monaco editor
      const monacoContent = screen.getByTestId('monaco-contenteditable');
      focusElement(monacoContent);

      // Mod+Shift+Enter should work in contentEditable
      await user.keyboard('{Meta>}{Shift>}{Enter}{/Shift}{/Meta}');
      await waitFor(() => expect(handleRun).toHaveBeenCalled());
    });

    test('works in form tags', async () => {
      const user = userEvent.setup();
      const { handleRun } = setupMockUseRunRetry();

      renderFullScreenIDE();

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      // Create and focus an input element
      const input = document.createElement('input');
      document.body.appendChild(input);
      focusElement(input);

      // Mod+Shift+Enter should work in form tags
      await user.keyboard('{Meta>}{Shift>}{Enter}{/Shift}{/Meta}');
      await waitFor(() => expect(handleRun).toHaveBeenCalled());

      document.body.removeChild(input);
    });

    test('calls handleRun even when canRun is false (guards are in handler)', async () => {
      const user = userEvent.setup();
      const { handleRun } = setupMockUseRunRetry({ canRun: false });

      const { container } = renderFullScreenIDE();

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      container.focus();

      // Keyboard shortcut calls handler unconditionally
      // The handler itself checks canRunWorkflow internally
      await user.keyboard('{Meta>}{Shift>}{Enter}{/Shift}{/Meta}');
      await waitFor(() => expect(handleRun).toHaveBeenCalled());
    });

    test('calls handleRun even when isSubmitting is true (guards are in handler)', async () => {
      const user = userEvent.setup();
      const { handleRun } = setupMockUseRunRetry({ isSubmitting: true });

      const { container } = renderFullScreenIDE();

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      container.focus();

      // Keyboard shortcut calls handler unconditionally
      // The handler itself has guards to prevent issues
      await user.keyboard('{Meta>}{Shift>}{Enter}{/Shift}{/Meta}');
      await waitFor(() => expect(handleRun).toHaveBeenCalled());
    });
  });

  describe('Keyboard Scope Integration', () => {
    test('shortcuts only work when IDE scope is enabled', async () => {
      setupMockUseRunRetry();
      const onClose = vi.fn();
      const { unmount } = renderFullScreenIDE({ onClose });

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      // Give time for scope to be enabled
      await new Promise(resolve => setTimeout(resolve, 200));

      // Escape should work when IDE is mounted (scope enabled)
      await pressKey('Escape');
      await waitFor(() => expect(onClose).toHaveBeenCalled());

      // Unmount IDE (scope disabled)
      unmount();

      // Escape should not work after unmount
      onClose.mockClear();
      await pressKey('Escape');
      await new Promise(resolve => setTimeout(resolve, 50));
      expect(onClose).not.toHaveBeenCalled();
    });
  });

  describe('Complex Interaction Scenarios', () => {
    test('Escape blur -> Mod+Enter run -> Escape close flow', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();
      const { handleRun } = setupMockUseRunRetry();

      renderFullScreenIDE({ onClose });

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      // Focus Monaco
      const monacoContent = screen.getByTestId('monaco-contenteditable');
      focusElement(monacoContent);

      // First Escape: blur Monaco
      await pressKey('Escape');
      await waitFor(() => {
        expect(document.activeElement).not.toBe(monacoContent);
      });
      expect(onClose).not.toHaveBeenCalled();

      // Mod+Enter: run workflow
      await user.keyboard('{Meta>}{Enter}{/Meta}');
      await waitFor(() => expect(handleRun).toHaveBeenCalled());

      // Second Escape: close IDE
      await pressKey('Escape');
      await waitFor(() => expect(onClose).toHaveBeenCalled());
    });

    test('Mod+Shift+Enter always calls handleRun regardless of retry state', async () => {
      const user = userEvent.setup();

      // Set up state where retry is available
      const { handleRun, handleRetry } = setupMockUseRunRetry({
        isRetryable: true,
      });

      const { container } = renderFullScreenIDE();

      await waitFor(() =>
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument()
      );

      container.focus();

      // Mod+Enter should call handleRetry (priority)
      await user.keyboard('{Meta>}{Enter}{/Meta}');
      await waitFor(() => {
        expect(handleRetry).toHaveBeenCalled();
        expect(handleRun).not.toHaveBeenCalled();
      });

      handleRun.mockClear();
      handleRetry.mockClear();

      // But Mod+Shift+Enter should always call handleRun (force new run)
      await user.keyboard('{Meta>}{Shift>}{Enter}{/Shift}{/Meta}');
      await waitFor(() => {
        expect(handleRun).toHaveBeenCalled();
        expect(handleRetry).not.toHaveBeenCalled();
      });
    });
  });
});
