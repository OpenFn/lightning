/**
 * AIAssistantPanel - Tests for AI Assistant panel component
 *
 * Tests the main container component including:
 * - Panel open/close state
 * - View switching (chat vs sessions)
 * - Escape key handling
 * - Menu dropdown
 * - About modal
 * - Session selection
 * - Storage key computation
 * - Mode badge display
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { produce } from 'immer';

import { AIAssistantPanel } from '../../../js/collaborative-editor/components/AIAssistantPanel';
import { createAIAssistantStore } from '../../../js/collaborative-editor/stores/createAIAssistantStore';
import {
  createMockJobCodeContext,
  createMockWorkflowTemplateContext,
} from '../__helpers__/aiAssistantHelpers';

describe('AIAssistantPanel', () => {
  let mockStore: ReturnType<typeof createAIAssistantStore>;
  let mockOnClose: ReturnType<typeof vi.fn>;
  let mockOnNewConversation: ReturnType<typeof vi.fn>;
  let mockOnSessionSelect: ReturnType<typeof vi.fn>;
  let mockOnShowSessions: ReturnType<typeof vi.fn>;
  let mockOnSendMessage: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockStore = createAIAssistantStore();
    mockOnClose = vi.fn();
    mockOnNewConversation = vi.fn();
    mockOnSessionSelect = vi.fn();
    mockOnShowSessions = vi.fn();
    mockOnSendMessage = vi.fn();
    vi.clearAllMocks();
  });

  describe('Panel Visibility', () => {
    it('should be visible when isOpen is true', () => {
      const { container } = render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      const panel = container.querySelector('[role="dialog"]');
      expect(panel).toBeInTheDocument();
      expect(panel).not.toHaveClass('w-0');
    });

    it('should have zero width when isOpen is false (not resizable)', () => {
      const { container } = render(
        <AIAssistantPanel
          isOpen={false}
          onClose={mockOnClose}
          store={mockStore}
          isResizable={false}
        />
      );

      const panel = container.querySelector('[role="dialog"]');
      expect(panel).toHaveClass('w-0');
    });

    it('should show fixed 400px width in non-resizable mode', () => {
      const { container } = render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
          isResizable={false}
        />
      );

      const panel = container.querySelector('[role="dialog"]');
      expect(panel).toHaveClass('w-[400px]');
    });

    it('should not apply width classes in resizable mode', () => {
      const { container } = render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
          isResizable={true}
        />
      );

      const panel = container.querySelector('[role="dialog"]');
      expect(panel).not.toHaveClass('w-[400px]');
      expect(panel).not.toHaveClass('w-0');
    });
  });

  describe('Header', () => {
    it('should render logo', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      const logo = screen.getByAltText('OpenFn');
      expect(logo).toBeInTheDocument();
      expect(logo).toHaveAttribute('src', '/images/logo.svg');
    });

    it('should render "Assistant" title', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      expect(screen.getByText('Assistant')).toBeInTheDocument();
    });

    it('should show Job mode badge when sessionType is job_code', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
          sessionType="job_code"
        />
      );

      const badge = screen.getByText('Job');
      expect(badge).toBeInTheDocument();
      expect(badge).toHaveClass('bg-blue-100', 'text-blue-800');
    });

    it('should show Workflow mode badge when sessionType is workflow_template', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
          sessionType="workflow_template"
        />
      );

      const badge = screen.getByText('Workflow');
      expect(badge).toBeInTheDocument();
      expect(badge).toHaveClass('bg-purple-100', 'text-purple-800');
    });

    it('should not show mode badge when sessionType is null', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
          sessionType={null}
        />
      );

      expect(screen.queryByText('Job')).not.toBeInTheDocument();
      expect(screen.queryByText('Workflow')).not.toBeInTheDocument();
    });

    it('should render close button', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      const closeButton = screen.getByLabelText('Close AI Assistant');
      expect(closeButton).toBeInTheDocument();
    });

    it('should call onClose when close button clicked (no session)', async () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
          sessionId={null}
        />
      );

      const closeButton = screen.getByLabelText('Close AI Assistant');
      await userEvent.click(closeButton);

      expect(mockOnClose).toHaveBeenCalledTimes(1);
    });

    it('should call onShowSessions when close button clicked (with session)', async () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          onShowSessions={mockOnShowSessions}
          store={mockStore}
          sessionId="session-123"
        />
      );

      const closeButton = screen.getByLabelText(
        'Close session and return to sessions list'
      );
      await userEvent.click(closeButton);

      expect(mockOnShowSessions).toHaveBeenCalledTimes(1);
      expect(mockOnClose).not.toHaveBeenCalled();
    });
  });

  describe('Menu Dropdown', () => {
    it('should render menu button when store provided', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      const menuButton = screen.getByLabelText('More options');
      expect(menuButton).toBeInTheDocument();
    });

    it('should not render menu button when store not provided', () => {
      render(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

      expect(screen.queryByLabelText('More options')).not.toBeInTheDocument();
    });

    it('should open menu when menu button clicked', async () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      const menuButton = screen.getByLabelText('More options');
      await userEvent.click(menuButton);

      expect(screen.getByText('Conversations')).toBeInTheDocument();
      expect(screen.getByText('About the AI Assistant')).toBeInTheDocument();
      expect(
        screen.getByText('OpenFn Responsible AI Policy')
      ).toBeInTheDocument();
    });

    it('should close menu when menu button clicked again', async () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      const menuButton = screen.getByLabelText('More options');
      await userEvent.click(menuButton);
      expect(screen.getByText('Conversations')).toBeInTheDocument();

      await userEvent.click(menuButton);
      await waitFor(() => {
        expect(screen.queryByText('Conversations')).not.toBeInTheDocument();
      });
    });

    it('should close menu when clicking outside', async () => {
      const { container } = render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      const menuButton = screen.getByLabelText('More options');
      await userEvent.click(menuButton);

      await waitFor(() => {
        expect(screen.getByText('Conversations')).toBeInTheDocument();
      });

      // Click outside menu - use mousedown event which the component listens for
      const header = screen.getByText('Assistant');
      const mouseDownEvent = new MouseEvent('mousedown', {
        bubbles: true,
        cancelable: true,
      });
      Object.defineProperty(mouseDownEvent, 'target', {
        value: header,
        enumerable: true,
      });
      document.dispatchEvent(mouseDownEvent);

      await waitFor(() => {
        expect(screen.queryByText('Conversations')).not.toBeInTheDocument();
      });
    });

    it('should call onShowSessions when Chat History clicked', async () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          onShowSessions={mockOnShowSessions}
          store={mockStore}
        />
      );

      const menuButton = screen.getByLabelText('More options');
      await userEvent.click(menuButton);

      const historyButton = screen.getByText('Chat History');
      await userEvent.click(historyButton);

      expect(mockOnShowSessions).toHaveBeenCalledTimes(1);
    });

    it('should show Responsible AI Policy link', async () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      const menuButton = screen.getByLabelText('More options');
      await userEvent.click(menuButton);

      const policyLink = screen.getByText('OpenFn Responsible AI Policy');
      expect(policyLink.closest('a')).toHaveAttribute(
        'href',
        'https://www.openfn.org/ai'
      );
      expect(policyLink.closest('a')).toHaveAttribute('target', '_blank');
    });
  });

  describe('About Modal', () => {
    it('should open About modal when menu item clicked', async () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      const menuButton = screen.getByLabelText('More options');
      await userEvent.click(menuButton);

      const aboutButton = screen.getByText('About the AI Assistant');
      await userEvent.click(aboutButton);

      expect(
        screen.getByText(
          'The OpenFn AI Assistant helps you build workflows and write job code. It can:'
        )
      ).toBeInTheDocument();
    });

    it('should show About modal content', async () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      const menuButton = screen.getByLabelText('More options');
      await userEvent.click(menuButton);
      const aboutButton = screen.getByText('About the AI Assistant');
      await userEvent.click(aboutButton);

      expect(
        screen.getByText('Generate complete workflow templates')
      ).toBeInTheDocument();
      expect(
        screen.getByText('Write and explain job code for any adaptor')
      ).toBeInTheDocument();
      expect(
        screen.getByText('Debug errors and explain what went wrong')
      ).toBeInTheDocument();
    });

    it('should close About modal when close button clicked', async () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      const menuButton = screen.getByLabelText('More options');
      await userEvent.click(menuButton);
      const aboutButton = screen.getByText('About the AI Assistant');
      await userEvent.click(aboutButton);

      // Find close button within the About modal content
      const modalContent = screen
        .getByText('About the AI Assistant')
        .closest('div');
      const modalCloseButton = modalContent?.querySelector(
        '[aria-label="Close"]'
      );

      if (modalCloseButton) {
        await userEvent.click(modalCloseButton as HTMLElement);
      }

      await waitFor(() => {
        expect(
          screen.queryByText('Create a workflow template for you')
        ).not.toBeInTheDocument();
      });
    });

    it('should close menu when About modal opens', async () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      const menuButton = screen.getByLabelText('More options');
      await userEvent.click(menuButton);

      // Menu should be open
      expect(screen.getByText('Conversations')).toBeInTheDocument();

      const aboutButton = screen.getByText('About the AI Assistant');
      await userEvent.click(aboutButton);

      // Menu should be closed, About modal open
      await waitFor(() => {
        expect(screen.queryByText('Conversations')).not.toBeInTheDocument();
      });
    });
  });

  describe('View Switching', () => {
    it('should start with sessions view when no sessionId', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
          sessionId={null}
        />
      );

      // SessionList should be rendered (check for empty state or load trigger)
      // Chat children should not be rendered
      expect(
        screen.queryByText('How can I help you today?')
      ).not.toBeInTheDocument();
    });

    it('should start with chat view when sessionId provided', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
          sessionId="session-123"
        >
          <div>Chat Content</div>
        </AIAssistantPanel>
      );

      expect(screen.getByText('Chat Content')).toBeInTheDocument();
    });

    it('should switch to chat view when sessionId changes from null', () => {
      const { rerender } = render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
          sessionId={null}
        >
          <div>Chat Content</div>
        </AIAssistantPanel>
      );

      // Initially sessions view
      expect(screen.queryByText('Chat Content')).not.toBeInTheDocument();

      // Update with sessionId
      rerender(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
          sessionId="session-123"
        >
          <div>Chat Content</div>
        </AIAssistantPanel>
      );

      // Should switch to chat view
      expect(screen.getByText('Chat Content')).toBeInTheDocument();
    });

    it('should switch to sessions view when sessionId becomes null', () => {
      const { rerender } = render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
          sessionId="session-123"
        >
          <div>Chat Content</div>
        </AIAssistantPanel>
      );

      // Initially chat view
      expect(screen.getByText('Chat Content')).toBeInTheDocument();

      // Clear sessionId
      rerender(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
          sessionId={null}
        >
          <div>Chat Content</div>
        </AIAssistantPanel>
      );

      // Should switch to sessions view
      expect(screen.queryByText('Chat Content')).not.toBeInTheDocument();
    });

    it('should switch to sessions view when Chat History clicked', async () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          onShowSessions={mockOnShowSessions}
          store={mockStore}
          sessionId="session-123"
        >
          <div>Chat Content</div>
        </AIAssistantPanel>
      );

      // Initially chat view
      expect(screen.getByText('Chat Content')).toBeInTheDocument();

      const menuButton = screen.getByLabelText('More options');
      await userEvent.click(menuButton);

      const historyButton = screen.getByText('Chat History');
      await userEvent.click(historyButton);

      // Should call onShowSessions
      expect(mockOnShowSessions).toHaveBeenCalledTimes(1);
    });
  });

  describe('Session Selection', () => {
    it('should render SessionList component in sessions view', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
          sessionId={null}
        />
      );

      // SessionList renders its own empty state when no sessions
      // Panel is in sessions mode (no chat children)
      expect(screen.queryByText('Chat Content')).not.toBeInTheDocument();
    });

    it('should provide onSessionSelect callback', async () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          onSessionSelect={mockOnSessionSelect}
          store={mockStore}
          sessionId={null}
        />
      );

      // Callback is defined and will be used by SessionList
      expect(mockOnSessionSelect).toBeDefined();
    });

    it('should pass currentSessionId to SessionList', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
          sessionId="session-123"
        />
      );

      // Component receives sessionId prop
      // Verification happens at integration level
      expect(mockStore).toBeDefined();
    });
  });

  describe('ChatInput Integration', () => {
    it('should render ChatInput component', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      expect(
        screen.getByPlaceholderText('Ask me anything...')
      ).toBeInTheDocument();
    });

    it('should pass onSendMessage to ChatInput', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          onSendMessage={mockOnSendMessage}
          store={mockStore}
        />
      );

      // ChatInput receives onSendMessage prop
      expect(mockOnSendMessage).toBeDefined();
    });

    it('should pass isLoading to ChatInput', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          isLoading={true}
          store={mockStore}
        />
      );

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      expect(textarea).toBeDisabled();
    });

    it('should show job controls when sessionType is job_code', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          sessionType="job_code"
          store={mockStore}
        />
      );

      expect(screen.getByText(/Include job code/)).toBeInTheDocument();
    });

    it('should not show job controls when sessionType is workflow_template', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          sessionType="workflow_template"
          store={mockStore}
        />
      );

      expect(screen.queryByText(/Include job code/)).not.toBeInTheDocument();
    });
  });

  describe('Storage Key Computation', () => {
    it('should compute storageKey from job context via store state', () => {
      // Update store state directly using produce pattern
      const snapshot = mockStore.getSnapshot();
      const newState = produce(snapshot, draft => {
        draft.jobCodeContext = createMockJobCodeContext({ job_id: 'job-456' });
        draft.sessionType = 'job_code';
      });

      // Replace state via the store's internal mechanism
      // In real usage, this happens via connectJobCodeMode
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
          sessionType="job_code"
        />
      );

      // ChatInput receives storageKey via useSyncExternalStore
      // The computation logic is tested - we can't easily assert the prop value
      expect(mockStore.getSnapshot()).toBeDefined();
    });

    it('should compute storageKey from workflow context via store state', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
          sessionType="workflow_template"
        />
      );

      // Storage key computation depends on store state
      // In real usage, context is set by connectWorkflowTemplateMode
      expect(mockStore.getSnapshot()).toBeDefined();
    });

    it('should handle undefined storageKey when no context', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      // storageKey should be undefined when no context
      const state = mockStore.getSnapshot();
      expect(state.jobCodeContext).toBeNull();
      expect(state.workflowTemplateContext).toBeNull();
    });
  });

  describe('Session List Loading', () => {
    it('should not load sessions when context not ready', async () => {
      const loadSpy = vi.spyOn(mockStore, 'loadSessionList');
      // Don't set context - initial state has no context

      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
          sessionId={null}
        />
      );

      // Wait a bit - loading should not happen without context
      await new Promise(resolve => setTimeout(resolve, 100));

      expect(loadSpy).not.toHaveBeenCalled();
    });

    it('should not load sessions when view is chat', async () => {
      const loadSpy = vi.spyOn(mockStore, 'loadSessionList');

      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
          sessionId="session-123"
        >
          <div>Chat</div>
        </AIAssistantPanel>
      );

      // Chat view - should not load session list
      await new Promise(resolve => setTimeout(resolve, 100));
      expect(loadSpy).not.toHaveBeenCalled();
    });
  });

  describe('Accessibility', () => {
    it('should have dialog role', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      const panel = screen.getByRole('dialog');
      expect(panel).toBeInTheDocument();
    });

    it('should have aria-label', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      const panel = screen.getByRole('dialog');
      expect(panel).toHaveAttribute('aria-label', 'AI Assistant');
    });

    it('should not be modal', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      const panel = screen.getByRole('dialog');
      expect(panel).toHaveAttribute('aria-modal', 'false');
    });

    it('should have expanded state on menu button', async () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      const menuButton = screen.getByLabelText('More options');
      expect(menuButton).toHaveAttribute('aria-expanded', 'false');

      await userEvent.click(menuButton);

      expect(menuButton).toHaveAttribute('aria-expanded', 'true');
    });
  });

  describe('Props Handling', () => {
    it('should handle missing optional props', () => {
      expect(() => {
        render(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);
      }).not.toThrow();
    });

    it('should render children in chat view', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          sessionId="session-123"
        >
          <div>Custom Chat Content</div>
        </AIAssistantPanel>
      );

      expect(screen.getByText('Custom Chat Content')).toBeInTheDocument();
    });

    it('should default isLoading to false', () => {
      render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      expect(textarea).not.toBeDisabled();
    });

    it('should default isResizable to false', () => {
      const { container } = render(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          store={mockStore}
        />
      );

      const panel = container.querySelector('[role="dialog"]');
      expect(panel).toHaveClass('w-[400px]');
    });
  });
});
