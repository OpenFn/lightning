/**
 * LoadingBoundary Component Tests
 *
 * Tests for LoadingBoundary component that acts as an async boundary,
 * waiting for Y.Doc to sync before rendering children.
 *
 * Test Coverage:
 * - Renders loading screen when session.isSynced = false
 * - Renders loading screen when workflow = null
 * - Renders children when session.isSynced = true AND workflow !== null
 * - Shows correct loading message
 * - Prevents race conditions from rendering before sync
 */

import { render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import { LoadingBoundary } from '../../../js/collaborative-editor/components/LoadingBoundary';
import * as useSessionModule from '../../../js/collaborative-editor/hooks/useSession';
import * as useSessionContextModule from '../../../js/collaborative-editor/hooks/useSessionContext';
import * as useWorkflowModule from '../../../js/collaborative-editor/hooks/useWorkflow';
import type { SessionState } from '../../../js/collaborative-editor/stores/createSessionStore';
import type { Workflow } from '../../../js/collaborative-editor/types/workflow';

// Mock hooks
const mockUseSession = vi.spyOn(useSessionModule, 'useSession');
const mockUseSessionContextLoading = vi.spyOn(
  useSessionContextModule,
  'useSessionContextLoading'
);
const mockUseWorkflowState = vi.spyOn(useWorkflowModule, 'useWorkflowState');

// Mock session state factory
const createMockSessionState = (
  overrides?: Partial<SessionState>
): SessionState => ({
  ydoc: null,
  provider: null,
  awareness: null,
  userData: null,
  isConnected: false,
  isSynced: false,
  settled: false,
  lastStatus: null,
  ...overrides,
});

// Mock workflow factory
const createMockWorkflow = (overrides?: Partial<Workflow>): Workflow => ({
  id: 'workflow-1',
  name: 'Test Workflow',
  jobs: [],
  triggers: [],
  edges: [],
  ...overrides,
});

describe('LoadingBoundary', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // By default, mock session context as loaded (not loading)
    mockUseSessionContextLoading.mockReturnValue(false);
  });

  describe('loading states', () => {
    test('renders loading screen when session.isSynced is false', () => {
      // Session not synced yet
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isConnected: true,
          isSynced: false,
        })
      );

      // Workflow is null
      mockUseWorkflowState.mockReturnValue(null);

      render(
        <LoadingBoundary>
          <div data-testid="child-content">Child Content</div>
        </LoadingBoundary>
      );

      // Should show loading screen
      expect(screen.queryByTestId('child-content')).not.toBeInTheDocument();
      expect(screen.getByText('Loading workflow')).toBeInTheDocument();
    });

    test('renders loading screen when workflow is null', () => {
      // Session is synced
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isConnected: true,
          isSynced: true,
        })
      );

      // But workflow hasn't been populated yet
      mockUseWorkflowState.mockReturnValue(null);

      render(
        <LoadingBoundary>
          <div data-testid="child-content">Child Content</div>
        </LoadingBoundary>
      );

      // Should show loading screen
      expect(screen.queryByTestId('child-content')).not.toBeInTheDocument();
      expect(screen.getByText('Loading workflow')).toBeInTheDocument();
    });

    test('renders loading screen when both conditions are false', () => {
      // Neither synced nor workflow available
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isConnected: false,
          isSynced: false,
        })
      );

      mockUseWorkflowState.mockReturnValue(null);

      render(
        <LoadingBoundary>
          <div data-testid="child-content">Child Content</div>
        </LoadingBoundary>
      );

      // Should show loading screen
      expect(screen.queryByTestId('child-content')).not.toBeInTheDocument();
      expect(screen.getByText('Loading workflow')).toBeInTheDocument();
    });
  });

  describe('ready state', () => {
    test('renders children when session.isSynced is true AND workflow is not null', () => {
      // Session is synced
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isConnected: true,
          isSynced: true,
          settled: true,
        })
      );

      // Workflow is available
      mockUseWorkflowState.mockReturnValue(createMockWorkflow());

      render(
        <LoadingBoundary>
          <div data-testid="child-content">Child Content</div>
        </LoadingBoundary>
      );

      // Should render children
      expect(screen.getByTestId('child-content')).toBeInTheDocument();
      expect(screen.getByText('Child Content')).toBeInTheDocument();

      // Should NOT show loading screen
      expect(screen.queryByText('Loading workflow')).not.toBeInTheDocument();
    });

    test('renders multiple children when ready', () => {
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isConnected: true,
          isSynced: true,
          settled: true,
        })
      );

      mockUseWorkflowState.mockReturnValue(createMockWorkflow());

      render(
        <LoadingBoundary>
          <div data-testid="child-1">Child 1</div>
          <div data-testid="child-2">Child 2</div>
          <div data-testid="child-3">Child 3</div>
        </LoadingBoundary>
      );

      // All children should be rendered
      expect(screen.getByTestId('child-1')).toBeInTheDocument();
      expect(screen.getByTestId('child-2')).toBeInTheDocument();
      expect(screen.getByTestId('child-3')).toBeInTheDocument();
    });
  });

  describe('loading message', () => {
    test('shows correct loading message', () => {
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isSynced: false,
        })
      );

      mockUseWorkflowState.mockReturnValue(null);

      render(
        <LoadingBoundary>
          <div>Content</div>
        </LoadingBoundary>
      );

      expect(screen.getByText('Loading workflow')).toBeInTheDocument();
    });

    test('loading screen has proper structure', () => {
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isSynced: false,
        })
      );

      mockUseWorkflowState.mockReturnValue(null);

      const { container } = render(
        <LoadingBoundary>
          <div>Content</div>
        </LoadingBoundary>
      );

      // Check for flex container with centering
      const flexContainer = container.querySelector(
        '.flex.items-center.justify-center'
      );
      expect(flexContainer).toBeInTheDocument();

      // Check for loading text
      const loadingText = container.querySelector('.text-gray-600');
      expect(loadingText).toBeInTheDocument();
      expect(loadingText).toHaveTextContent('Loading workflow');

      // Check for animated ping spinner
      const pingSpin = container.querySelector('.animate-ping');
      expect(pingSpin).toBeInTheDocument();
      expect(pingSpin).toHaveClass('rounded-full');
      expect(pingSpin).toHaveClass('bg-primary-400');
    });
  });

  describe('edge cases', () => {
    test('handles empty children gracefully', () => {
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isConnected: true,
          isSynced: true,
          settled: true,
        })
      );

      mockUseWorkflowState.mockReturnValue(createMockWorkflow());

      const { container } = render(<LoadingBoundary>{null}</LoadingBoundary>);

      // Should render without errors
      expect(container).toBeInTheDocument();
      expect(screen.queryByText('Loading workflow')).not.toBeInTheDocument();
    });

    test('handles isConnected false but isSynced true (edge case)', () => {
      // This shouldn't happen in practice, but test defensive behavior
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isConnected: false,
          isSynced: true, // Unusual state
          settled: true,
        })
      );

      mockUseWorkflowState.mockReturnValue(createMockWorkflow());

      render(
        <LoadingBoundary>
          <div data-testid="child-content">Child Content</div>
        </LoadingBoundary>
      );

      // Should render children since settled is true
      expect(screen.getByTestId('child-content')).toBeInTheDocument();
    });

    test('handles workflow with minimal data', () => {
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isConnected: true,
          isSynced: true,
          settled: true,
        })
      );

      // Workflow exists but with empty arrays
      mockUseWorkflowState.mockReturnValue(
        createMockWorkflow({
          jobs: [],
          triggers: [],
          edges: [],
        })
      );

      render(
        <LoadingBoundary>
          <div data-testid="child-content">Child Content</div>
        </LoadingBoundary>
      );

      // Should render children - workflow exists even if empty
      expect(screen.getByTestId('child-content')).toBeInTheDocument();
    });
  });

  describe('bug prevention', () => {
    test('prevents rendering before sync (Bug 1: nodes collapsing)', () => {
      // Simulates scenario where positions not yet synced
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isConnected: true,
          isSynced: false, // Positions not synced yet
        })
      );

      mockUseWorkflowState.mockReturnValue(null);

      render(
        <LoadingBoundary>
          <div data-testid="workflow-diagram">Workflow Diagram</div>
        </LoadingBoundary>
      );

      // Should NOT render diagram until synced
      expect(screen.queryByTestId('workflow-diagram')).not.toBeInTheDocument();
      expect(screen.getByText('Loading workflow')).toBeInTheDocument();
    });

    test('prevents rendering before workflow loaded (Bug 2: old version errors)', () => {
      // Simulates scenario where lock_version not yet synced
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isConnected: true,
          isSynced: true,
        })
      );

      mockUseWorkflowState.mockReturnValue(null); // Workflow not populated yet

      render(
        <LoadingBoundary>
          <div data-testid="workflow-editor">Workflow Editor</div>
        </LoadingBoundary>
      );

      // Should NOT render editor until workflow available
      expect(screen.queryByTestId('workflow-editor')).not.toBeInTheDocument();
      expect(screen.getByText('Loading workflow')).toBeInTheDocument();
    });

    test('allows rendering only when both conditions met', () => {
      // First: not synced
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isSynced: false,
          settled: false,
        })
      );
      mockUseWorkflowState.mockReturnValue(null);

      const { rerender } = render(
        <LoadingBoundary>
          <div data-testid="content">Content</div>
        </LoadingBoundary>
      );

      expect(screen.queryByTestId('content')).not.toBeInTheDocument();

      // Second: synced but no workflow
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isSynced: true,
          settled: true,
        })
      );
      mockUseWorkflowState.mockReturnValue(null);

      rerender(
        <LoadingBoundary>
          <div data-testid="content">Content</div>
        </LoadingBoundary>
      );

      expect(screen.queryByTestId('content')).not.toBeInTheDocument();

      // Third: both conditions met
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isSynced: true,
          settled: true,
        })
      );
      mockUseWorkflowState.mockReturnValue(createMockWorkflow());

      rerender(
        <LoadingBoundary>
          <div data-testid="content">Content</div>
        </LoadingBoundary>
      );

      // NOW it should render
      expect(screen.getByTestId('content')).toBeInTheDocument();
    });
  });

  describe('integration with hooks', () => {
    test('calls useSession hook', () => {
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isSynced: true,
          settled: true,
        })
      );
      mockUseWorkflowState.mockReturnValue(createMockWorkflow());

      render(
        <LoadingBoundary>
          <div>Content</div>
        </LoadingBoundary>
      );

      expect(mockUseSession).toHaveBeenCalled();
    });

    test('calls useWorkflowState hook with correct selector', () => {
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isSynced: true,
          settled: true,
        })
      );
      mockUseWorkflowState.mockReturnValue(createMockWorkflow());

      render(
        <LoadingBoundary>
          <div>Content</div>
        </LoadingBoundary>
      );

      expect(mockUseWorkflowState).toHaveBeenCalled();

      // Verify selector extracts workflow
      const selector = mockUseWorkflowState.mock.calls[0][0];
      const mockState = { workflow: createMockWorkflow() };
      expect(selector(mockState)).toBe(mockState.workflow);
    });
  });

  describe('disconnection scenarios (offline editing)', () => {
    test('renders cached workflow when disconnected', () => {
      // Simulates: User was connected, then lost connection
      // but cached workflow data still exists in Y.Doc
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isConnected: false, // Lost connection
          isSynced: false,
          settled: false, // No longer settled
        })
      );

      // Cached workflow still available from Y.Doc
      mockUseWorkflowState.mockReturnValue(createMockWorkflow());

      render(
        <LoadingBoundary>
          <div data-testid="child-content">Child Content</div>
        </LoadingBoundary>
      );

      // Should render children with cached data
      expect(screen.getByTestId('child-content')).toBeInTheDocument();
      expect(screen.queryByText('Loading workflow')).not.toBeInTheDocument();
    });

    test('shows loading on initial load when disconnected', () => {
      // Simulates: User navigates to page while offline
      // No cached workflow data available
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isConnected: false,
          isSynced: false,
          settled: false,
        })
      );

      // No workflow data available (initial load)
      mockUseWorkflowState.mockReturnValue(null);

      render(
        <LoadingBoundary>
          <div data-testid="child-content">Child Content</div>
        </LoadingBoundary>
      );

      // Should show loading screen (can't render without data)
      expect(screen.queryByTestId('child-content')).not.toBeInTheDocument();
      expect(screen.getByText('Loading workflow')).toBeInTheDocument();
    });

    test('transitions from connected to disconnected gracefully', () => {
      // Start: Connected and synced
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isConnected: true,
          isSynced: true,
          settled: true,
        })
      );
      mockUseWorkflowState.mockReturnValue(createMockWorkflow());

      const { rerender } = render(
        <LoadingBoundary>
          <div data-testid="content">Content</div>
        </LoadingBoundary>
      );

      // Should render content
      expect(screen.getByTestId('content')).toBeInTheDocument();

      // Disconnect: Connection lost but workflow cached
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isConnected: false, // Disconnected
          isSynced: false,
          settled: false,
        })
      );
      mockUseWorkflowState.mockReturnValue(createMockWorkflow()); // Cached

      rerender(
        <LoadingBoundary>
          <div data-testid="content">Content</div>
        </LoadingBoundary>
      );

      // Should STILL render content (graceful degradation)
      expect(screen.getByTestId('content')).toBeInTheDocument();
      expect(screen.queryByText('Loading workflow')).not.toBeInTheDocument();
    });

    test('transitions from disconnected to reconnected', () => {
      // Start: Disconnected with cached workflow
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isConnected: false,
          isSynced: false,
          settled: false,
        })
      );
      mockUseWorkflowState.mockReturnValue(createMockWorkflow());

      const { rerender } = render(
        <LoadingBoundary>
          <div data-testid="content">Content</div>
        </LoadingBoundary>
      );

      // Should render with cached data
      expect(screen.getByTestId('content')).toBeInTheDocument();

      // Reconnect: Connection restored and syncing
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isConnected: true,
          isSynced: false, // Syncing in progress
          settled: false,
        })
      );
      mockUseWorkflowState.mockReturnValue(createMockWorkflow());

      rerender(
        <LoadingBoundary>
          <div data-testid="content">Content</div>
        </LoadingBoundary>
      );

      // Should STILL render (not initial load anymore)
      expect(screen.getByTestId('content')).toBeInTheDocument();

      // Finally: Reconnected and synced
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isConnected: true,
          isSynced: true,
          settled: true,
        })
      );
      mockUseWorkflowState.mockReturnValue(createMockWorkflow());

      rerender(
        <LoadingBoundary>
          <div data-testid="content">Content</div>
        </LoadingBoundary>
      );

      // Should continue rendering
      expect(screen.getByTestId('content')).toBeInTheDocument();
    });

    test('prevents rendering during initial load even when connected', () => {
      // Simulates: Page just loaded, connection established but no data yet
      mockUseSession.mockReturnValue(
        createMockSessionState({
          isConnected: true,
          isSynced: false,
          settled: false,
        })
      );

      // No workflow data yet (initial load)
      mockUseWorkflowState.mockReturnValue(null);

      render(
        <LoadingBoundary>
          <div data-testid="content">Content</div>
        </LoadingBoundary>
      );

      // Should show loading (must wait for initial sync)
      expect(screen.queryByTestId('content')).not.toBeInTheDocument();
      expect(screen.getByText('Loading workflow')).toBeInTheDocument();
    });
  });
});
