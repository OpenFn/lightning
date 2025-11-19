/**
 * Inspector Keyboard Shortcut Tests
 *
 * Tests the Inspector component's keyboard shortcuts.
 * Priority system (PANEL priority 10) is tested in keyboard-scopes.test.tsx.
 */

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type React from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { KeyboardProvider } from '#/collaborative-editor/keyboard';

import { Inspector } from '#/collaborative-editor/components/inspector';
import { LiveViewActionsProvider } from '#/collaborative-editor/contexts/LiveViewActionsContext';
import { SessionContext } from '#/collaborative-editor/contexts/SessionProvider';
import { StoreContext } from '#/collaborative-editor/contexts/StoreProvider';
import { createSessionStore } from '#/collaborative-editor/stores/createSessionStore';
import { createStores } from '../__helpers__/storeProviderHelpers';

// Mock child inspector components to avoid needing full workflow setup
vi.mock('#/collaborative-editor/components/inspector/JobInspector', () => ({
  JobInspector: ({ onClose }: any) => (
    <div data-testid="job-inspector">
      <button onClick={onClose}>Close</button>
    </div>
  ),
}));

vi.mock('#/collaborative-editor/components/inspector/TriggerInspector', () => ({
  TriggerInspector: ({ onClose }: any) => (
    <div data-testid="trigger-inspector">
      <button onClick={onClose}>Close</button>
    </div>
  ),
}));

vi.mock('#/collaborative-editor/components/inspector/EdgeInspector', () => ({
  EdgeInspector: ({ onClose }: any) => (
    <div data-testid="edge-inspector">
      <button onClick={onClose}>Close</button>
    </div>
  ),
}));

vi.mock('#/collaborative-editor/components/inspector/WorkflowSettings', () => ({
  WorkflowSettings: () => <div data-testid="workflow-settings">Settings</div>,
}));

vi.mock('#/collaborative-editor/components/inspector/CodeViewPanel', () => ({
  CodeViewPanel: () => <div data-testid="code-view-panel">Code</div>,
}));

/**
 * Creates a test wrapper with all required providers
 */
function createTestWrapper() {
  const stores = createStores();
  const sessionStore = createSessionStore();

  const mockLiveViewActions = {
    pushEvent: vi.fn(),
    pushEventTo: vi.fn(),
    handleEvent: vi.fn(() => vi.fn()),
    navigate: vi.fn(),
  };

  return function Wrapper({ children }: { children: React.ReactNode }) {
    return (
      <KeyboardProvider>
        <SessionContext.Provider value={{ sessionStore, isNewWorkflow: false }}>
          <LiveViewActionsProvider actions={mockLiveViewActions}>
            <StoreContext.Provider value={stores}>
              {children}
            </StoreContext.Provider>
          </LiveViewActionsProvider>
        </SessionContext.Provider>
      </KeyboardProvider>
    );
  };
}

describe('Inspector keyboard shortcuts', () => {
  beforeEach(() => {
    // Clear URL params between tests
    window.history.pushState({}, '', window.location.pathname);
  });

  describe('Escape - Close inspector/settings/code panel', () => {
    test('closes inspector panel when job node is selected', async () => {
      const user = userEvent.setup();
      const mockClose = vi.fn();

      render(
        <Inspector
          currentNode={{
            id: 'job-1',
            type: 'job',
            node: {
              id: 'job-1',
              name: 'Test Job',
              body: 'console.log("test");',
            } as any,
          }}
          onClose={mockClose}
          onOpenRunPanel={vi.fn()}
        />,
        { wrapper: createTestWrapper() }
      );

      await user.keyboard('{Escape}');

      expect(mockClose).toHaveBeenCalledTimes(1);
    });

    test('closes inspector panel when trigger node is selected', async () => {
      const user = userEvent.setup();
      const mockClose = vi.fn();

      render(
        <Inspector
          currentNode={{
            id: 'trigger-1',
            type: 'trigger',
            node: { id: 'trigger-1', type: 'webhook' } as any,
          }}
          onClose={mockClose}
          onOpenRunPanel={vi.fn()}
        />,
        { wrapper: createTestWrapper() }
      );

      await user.keyboard('{Escape}');

      expect(mockClose).toHaveBeenCalledTimes(1);
    });

    test('closes inspector panel when edge is selected', async () => {
      const user = userEvent.setup();
      const mockClose = vi.fn();

      render(
        <Inspector
          currentNode={{
            id: 'edge-1',
            type: 'edge',
            node: {
              id: 'edge-1',
              source_job_id: 'job-1',
              target_job_id: 'job-2',
            } as any,
          }}
          onClose={mockClose}
          onOpenRunPanel={vi.fn()}
        />,
        { wrapper: createTestWrapper() }
      );

      await user.keyboard('{Escape}');

      expect(mockClose).toHaveBeenCalledTimes(1);
    });

    test('closes settings panel by clearing URL param', async () => {
      const user = userEvent.setup();
      const mockClose = vi.fn();

      // Set URL search params to simulate settings panel open
      const params = new URLSearchParams();
      params.set('panel', 'settings');
      window.history.pushState({}, '', `?${params.toString()}`);

      render(
        <Inspector
          currentNode={{ id: null, type: null, node: null }}
          onClose={mockClose}
          onOpenRunPanel={vi.fn()}
        />,
        { wrapper: createTestWrapper() }
      );

      // Verify settings panel is showing
      expect(screen.getByTestId('workflow-settings')).toBeInTheDocument();

      await user.keyboard('{Escape}');

      // URL param should be cleared
      const searchParams = new URLSearchParams(window.location.search);
      expect(searchParams.get('panel')).toBeNull();

      // onClose should NOT be called - only URL updated
      expect(mockClose).not.toHaveBeenCalled();
    });

    test('closes code panel by clearing URL param', async () => {
      const user = userEvent.setup();
      const mockClose = vi.fn();

      // Set URL search params to simulate code panel open
      const params = new URLSearchParams();
      params.set('panel', 'code');
      window.history.pushState({}, '', `?${params.toString()}`);

      render(
        <Inspector
          currentNode={{ id: null, type: null, node: null }}
          onClose={mockClose}
          onOpenRunPanel={vi.fn()}
        />,
        { wrapper: createTestWrapper() }
      );

      // Verify code panel is showing
      expect(screen.getByTestId('code-view-panel')).toBeInTheDocument();

      await user.keyboard('{Escape}');

      // URL param should be cleared
      const searchParams = new URLSearchParams(window.location.search);
      expect(searchParams.get('panel')).toBeNull();

      // onClose should NOT be called - only URL updated
      expect(mockClose).not.toHaveBeenCalled();
    });
  });

  describe('enableOnFormTags: true behavior', () => {
    test('works when focus is in input field', async () => {
      const user = userEvent.setup();
      const mockClose = vi.fn();

      render(
        <>
          <input data-testid="test-input" />
          <Inspector
            currentNode={{
              id: 'job-1',
              type: 'job',
              node: { id: 'job-1', name: 'Test Job' } as any,
            }}
            onClose={mockClose}
            onOpenRunPanel={vi.fn()}
          />
        </>,
        { wrapper: createTestWrapper() }
      );

      // Focus the input field
      const input = screen.getByTestId('test-input');
      await user.click(input);

      // Escape should still work
      await user.keyboard('{Escape}');

      expect(mockClose).toHaveBeenCalledTimes(1);
    });

    test('works when focus is in textarea', async () => {
      const user = userEvent.setup();
      const mockClose = vi.fn();

      render(
        <>
          <textarea data-testid="test-textarea" />
          <Inspector
            currentNode={{
              id: 'job-1',
              type: 'job',
              node: { id: 'job-1', name: 'Test Job' } as any,
            }}
            onClose={mockClose}
            onOpenRunPanel={vi.fn()}
          />
        </>,
        { wrapper: createTestWrapper() }
      );

      // Focus the textarea
      const textarea = screen.getByTestId('test-textarea');
      await user.click(textarea);

      // Escape should still work
      await user.keyboard('{Escape}');

      expect(mockClose).toHaveBeenCalledTimes(1);
    });

    test('works when focus is in select', async () => {
      const user = userEvent.setup();
      const mockClose = vi.fn();

      render(
        <>
          <select data-testid="test-select">
            <option value="1">Option 1</option>
            <option value="2">Option 2</option>
          </select>
          <Inspector
            currentNode={{
              id: 'job-1',
              type: 'job',
              node: { id: 'job-1', name: 'Test Job' } as any,
            }}
            onClose={mockClose}
            onOpenRunPanel={vi.fn()}
          />
        </>,
        { wrapper: createTestWrapper() }
      );

      // Focus the select
      const select = screen.getByTestId('test-select');
      await user.click(select);

      // Escape should still work
      await user.keyboard('{Escape}');

      expect(mockClose).toHaveBeenCalledTimes(1);
    });
  });

  describe('PANEL scope (lowest priority)', () => {
    test('Inspector uses PANEL scope for keyboard shortcuts', async () => {
      // This test documents that Inspector uses PANEL scope,
      // which is the lowest priority in the keyboard shortcuts system.
      // Higher priority scopes (MODAL, IDE, RUN_PANEL) should take
      // precedence over Inspector's Escape handler.
      //
      // Note: Testing scope interactions with other components
      // (IDE, ManualRunPanel, modals) is handled in separate
      // scope interaction tests.

      const user = userEvent.setup();
      const mockClose = vi.fn();

      render(
        <Inspector
          currentNode={{
            id: 'job-1',
            type: 'job',
            node: { id: 'job-1', name: 'Test Job' } as any,
          }}
          onClose={mockClose}
          onOpenRunPanel={vi.fn()}
        />,
        { wrapper: createTestWrapper() }
      );

      // Verify the shortcut works
      await user.keyboard('{Escape}');

      expect(mockClose).toHaveBeenCalled();
    });
  });

  describe('component rendering', () => {
    test('does not render when no node selected and no panel in URL', () => {
      const mockClose = vi.fn();

      const { container } = render(
        <Inspector
          currentNode={{ id: null, type: null, node: null }}
          onClose={mockClose}
          onOpenRunPanel={vi.fn()}
        />,
        { wrapper: createTestWrapper() }
      );

      // Component should not render anything
      expect(container.firstChild).toBeNull();
    });

    test('renders job inspector for job node type', () => {
      const mockClose = vi.fn();

      render(
        <Inspector
          currentNode={{
            id: 'job-1',
            type: 'job',
            node: { id: 'job-1', name: 'Test Job' } as any,
          }}
          onClose={mockClose}
          onOpenRunPanel={vi.fn()}
        />,
        { wrapper: createTestWrapper() }
      );

      expect(screen.getByTestId('job-inspector')).toBeInTheDocument();
    });

    test('renders trigger inspector for trigger node type', () => {
      const mockClose = vi.fn();

      render(
        <Inspector
          currentNode={{
            id: 'trigger-1',
            type: 'trigger',
            node: { id: 'trigger-1', type: 'webhook' } as any,
          }}
          onClose={mockClose}
          onOpenRunPanel={vi.fn()}
        />,
        { wrapper: createTestWrapper() }
      );

      expect(screen.getByTestId('trigger-inspector')).toBeInTheDocument();
    });

    test('renders edge inspector for edge type', () => {
      const mockClose = vi.fn();

      render(
        <Inspector
          currentNode={{
            id: 'edge-1',
            type: 'edge',
            node: {
              id: 'edge-1',
              source_job_id: 'job-1',
              target_job_id: 'job-2',
            } as any,
          }}
          onClose={mockClose}
          onOpenRunPanel={vi.fn()}
        />,
        { wrapper: createTestWrapper() }
      );

      expect(screen.getByTestId('edge-inspector')).toBeInTheDocument();
    });
  });
});
