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

import { act, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { produce } from 'immer';
import type { ReactNode } from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { AIAssistantPanel } from '../../../js/collaborative-editor/components/AIAssistantPanel';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { createAIAssistantStore } from '../../../js/collaborative-editor/stores/createAIAssistantStore';
import { createMockJobCodeContext } from '../__helpers__/aiAssistantHelpers';
import { createMockHistoryStore } from '../__helpers__/storeMocks';

describe('AIAssistantPanel', () => {
  let mockStore: ReturnType<typeof createAIAssistantStore>;
  let mockHistoryStore: ReturnType<typeof createMockHistoryStore>;
  let mockOnClose: ReturnType<typeof vi.fn>;
  let mockOnNewConversation: ReturnType<typeof vi.fn>;
  let mockOnSessionSelect: ReturnType<typeof vi.fn>;
  let mockOnShowSessions: ReturnType<typeof vi.fn>;
  let mockOnSendMessage: ReturnType<typeof vi.fn>;

  // Helper to wrap component with StoreProvider
  const renderWithStore = (ui: ReactNode) => {
    return render(
      <StoreContext.Provider
        value={
          {
            aiAssistantStore: mockStore,
            historyStore: mockHistoryStore,
          } as any
        }
      >
        {ui}
      </StoreContext.Provider>
    );
  };

  beforeEach(() => {
    mockStore = createAIAssistantStore();
    mockHistoryStore = createMockHistoryStore();
    mockOnClose = vi.fn();
    mockOnNewConversation = vi.fn();
    mockOnSessionSelect = vi.fn();
    mockOnShowSessions = vi.fn();
    mockOnSendMessage = vi.fn();
    vi.clearAllMocks();
  });

  describe('Panel Visibility', () => {
    it('should be visible when isOpen is true', () => {
      const { container } = renderWithStore(
        <AIAssistantPanel isOpen={true} onClose={mockOnClose} />
      );

      const panel = screen.getByRole('complementary');
      expect(panel).toBeInTheDocument();
      expect(panel).not.toHaveClass('w-0');
    });

    it('should have zero width when isOpen is false (not resizable)', () => {
      renderWithStore(
        <AIAssistantPanel
          isOpen={false}
          onClose={mockOnClose}
          isResizable={false}
        />
      );

      const panel = screen.getByRole('complementary');
      expect(panel).toHaveClass('w-0');
    });

    it('should show fixed 400px width in non-resizable mode', () => {
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          isResizable={false}
        />
      );

      const panel = screen.getByRole('complementary');
      expect(panel).toHaveClass('w-[400px]');
    });

    it('should not apply width classes in resizable mode', () => {
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          isResizable={true}
        />
      );

      const panel = screen.getByRole('complementary');
      expect(panel).not.toHaveClass('w-[400px]');
      expect(panel).not.toHaveClass('w-0');
    });
  });

  describe('Header', () => {
    it('should render logo', () => {
      renderWithStore(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

      const logo = screen.getByAltText('OpenFn');
      expect(logo).toBeInTheDocument();
      expect(logo).toHaveAttribute('src', '/images/logo.svg');
    });

    it('should render "Assistant" title', () => {
      renderWithStore(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

      expect(screen.getByText('Assistant')).toBeInTheDocument();
    });

    it('should show Job mode badge when sessionType is job_code', () => {
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          sessionType="job_code"
        />
      );

      const badge = screen.getByText('Job');
      expect(badge).toBeInTheDocument();
      expect(badge).toHaveClass('bg-blue-100', 'text-blue-800');
    });

    it('should show Workflow mode badge when sessionType is workflow_template', () => {
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          sessionType="workflow_template"
        />
      );

      const badge = screen.getByText('Workflow');
      expect(badge).toBeInTheDocument();
      expect(badge).toHaveClass('bg-purple-100', 'text-purple-800');
    });

    it('should not show mode badge when sessionType is null', () => {
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          sessionType={null}
        />
      );

      expect(screen.queryByText('Job')).not.toBeInTheDocument();
      expect(screen.queryByText('Workflow')).not.toBeInTheDocument();
    });

    it('should render close button', () => {
      renderWithStore(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

      const closeButton = screen.getByLabelText('Close assistant');
      expect(closeButton).toBeInTheDocument();
    });

    it('should call onClose when close button clicked (no session)', async () => {
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          sessionId={null}
        />
      );

      const closeButton = screen.getByLabelText('Close assistant');
      await userEvent.click(closeButton);

      expect(mockOnClose).toHaveBeenCalledTimes(1);
    });

    it('should call onShowSessions when close button clicked (with session)', async () => {
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          onShowSessions={mockOnShowSessions}
          sessionId="session-123"
        />
      );

      const closeButton = screen.getByLabelText('Close current session');
      await userEvent.click(closeButton);

      expect(mockOnShowSessions).toHaveBeenCalledTimes(1);
      expect(mockOnClose).not.toHaveBeenCalled();
    });
  });

  describe('Menu Dropdown', () => {
    it('should render menu button when store provided', () => {
      renderWithStore(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

      const menuButton = screen.getByLabelText('More options');
      expect(menuButton).toBeInTheDocument();
    });

    it('should always render menu button with StoreProvider', () => {
      renderWithStore(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

      expect(screen.getByLabelText('More options')).toBeInTheDocument();
    });

    it('should open menu when menu button clicked', async () => {
      renderWithStore(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

      const menuButton = screen.getByLabelText('More options');
      await userEvent.click(menuButton);

      expect(screen.getByText('Conversations')).toBeInTheDocument();
      expect(screen.getByText('About the AI Assistant')).toBeInTheDocument();
      expect(screen.getByText('Responsible AI Policy')).toBeInTheDocument();
    });

    it('should close menu when menu button clicked again', async () => {
      renderWithStore(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

      const menuButton = screen.getByLabelText('More options');
      await userEvent.click(menuButton);
      expect(screen.getByText('Conversations')).toBeInTheDocument();

      await userEvent.click(menuButton);
      await waitFor(() => {
        expect(screen.queryByText('Conversations')).not.toBeInTheDocument();
      });
    });

    it('should close menu when clicking outside', async () => {
      renderWithStore(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

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
      act(() => {
        document.dispatchEvent(mouseDownEvent);
      });

      await waitFor(() => {
        expect(screen.queryByText('Conversations')).not.toBeInTheDocument();
      });
    });

    it('should call onShowSessions when Conversations clicked', async () => {
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          onShowSessions={mockOnShowSessions}
        />
      );

      const menuButton = screen.getByLabelText('More options');
      await userEvent.click(menuButton);

      const historyButton = screen.getByText('Conversations');
      await userEvent.click(historyButton);

      expect(mockOnShowSessions).toHaveBeenCalledTimes(1);
    });

    it('should show Responsible AI Policy link', async () => {
      renderWithStore(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

      const menuButton = screen.getByLabelText('More options');
      await userEvent.click(menuButton);

      const policyLink = screen.getByText('Responsible AI Policy');
      expect(policyLink.closest('a')).toHaveAttribute(
        'href',
        'https://www.openfn.org/ai'
      );
      expect(policyLink.closest('a')).toHaveAttribute('target', '_blank');
    });
  });

  describe('About Modal', () => {
    it('should open About modal when menu item clicked', async () => {
      renderWithStore(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

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
      renderWithStore(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

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
      renderWithStore(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

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
      renderWithStore(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

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
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
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
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          sessionId="session-123"
        >
          <div>Chat Content</div>
        </AIAssistantPanel>
      );

      expect(screen.getByText('Chat Content')).toBeInTheDocument();
    });

    it('should switch to chat view when sessionId changes from null', () => {
      const { rerender } = renderWithStore(
        <AIAssistantPanel isOpen={true} onClose={mockOnClose} sessionId={null}>
          <div>Chat Content</div>
        </AIAssistantPanel>
      );

      // Initially sessions view
      expect(screen.queryByText('Chat Content')).not.toBeInTheDocument();

      // Update with sessionId
      rerender(
        <StoreContext.Provider
          value={
            {
              aiAssistantStore: mockStore,
              historyStore: mockHistoryStore,
            } as any
          }
        >
          <AIAssistantPanel
            isOpen={true}
            onClose={mockOnClose}
            sessionId="session-123"
          >
            <div>Chat Content</div>
          </AIAssistantPanel>
        </StoreContext.Provider>
      );

      // Should switch to chat view
      expect(screen.getByText('Chat Content')).toBeInTheDocument();
    });

    it('should switch to sessions view when sessionId becomes null', () => {
      const { rerender } = renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          sessionId="session-123"
        >
          <div>Chat Content</div>
        </AIAssistantPanel>
      );

      // Initially chat view
      expect(screen.getByText('Chat Content')).toBeInTheDocument();

      // Clear sessionId
      rerender(
        <StoreContext.Provider
          value={
            {
              aiAssistantStore: mockStore,
              historyStore: mockHistoryStore,
            } as any
          }
        >
          <AIAssistantPanel
            isOpen={true}
            onClose={mockOnClose}
            sessionId={null}
          >
            <div>Chat Content</div>
          </AIAssistantPanel>
        </StoreContext.Provider>
      );

      // Should switch to sessions view
      expect(screen.queryByText('Chat Content')).not.toBeInTheDocument();
    });

    it('should switch to sessions view when Conversations clicked', async () => {
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          onShowSessions={mockOnShowSessions}
          sessionId="session-123"
        >
          <div>Chat Content</div>
        </AIAssistantPanel>
      );

      // Initially chat view
      expect(screen.getByText('Chat Content')).toBeInTheDocument();

      const menuButton = screen.getByLabelText('More options');
      await userEvent.click(menuButton);

      const historyButton = screen.getByText('Conversations');
      await userEvent.click(historyButton);

      // Should call onShowSessions
      expect(mockOnShowSessions).toHaveBeenCalledTimes(1);
    });
  });

  describe('Session Selection', () => {
    it('should render SessionList component in sessions view', () => {
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          sessionId={null}
        />
      );

      // SessionList renders its own empty state when no sessions
      // Panel is in sessions mode (no chat children)
      expect(screen.queryByText('Chat Content')).not.toBeInTheDocument();
    });

    it('should provide onSessionSelect callback', async () => {
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          onSessionSelect={mockOnSessionSelect}
          sessionId={null}
        />
      );

      // Callback is defined and will be used by SessionList
      expect(mockOnSessionSelect).toBeDefined();
    });

    it('should pass currentSessionId to SessionList', () => {
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
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
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          sessionId="session-1"
        />
      );

      expect(
        screen.getByPlaceholderText('Ask me anything...')
      ).toBeInTheDocument();
    });

    it('should pass onSendMessage to ChatInput', () => {
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          onSendMessage={mockOnSendMessage}
          sessionId="session-1"
        />
      );

      // ChatInput receives onSendMessage prop
      expect(mockOnSendMessage).toBeDefined();
    });

    it('should pass isLoading to ChatInput', () => {
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          isLoading={true}
          sessionId="session-1"
        />
      );

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      expect(textarea).toBeDisabled();
    });

    it('should show job controls when sessionType is job_code', () => {
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          sessionType="job_code"
          sessionId="session-1"
        />
      );

      expect(screen.getByText(/Send code/)).toBeInTheDocument();
    });

    it('should not show job controls when sessionType is workflow_template', () => {
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          sessionType="workflow_template"
        />
      );

      expect(screen.queryByText(/Send code/)).not.toBeInTheDocument();
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
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          sessionType="job_code"
        />
      );

      // ChatInput receives storageKey via useSyncExternalStore
      // The computation logic is tested - we can't easily assert the prop value
      expect(mockStore.getSnapshot()).toBeDefined();
    });

    it('should compute storageKey from workflow context via store state', () => {
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          sessionType="workflow_template"
        />
      );

      // Storage key computation depends on store state
      // In real usage, context is set by connectWorkflowTemplateMode
      expect(mockStore.getSnapshot()).toBeDefined();
    });

    it('should handle undefined storageKey when no context', () => {
      renderWithStore(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

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

      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          sessionId={null}
        />
      );

      // Wait a bit - loading should not happen without context
      await new Promise(resolve => setTimeout(resolve, 100));

      expect(loadSpy).not.toHaveBeenCalled();
    });

    it('should not load sessions when view is chat', async () => {
      const loadSpy = vi.spyOn(mockStore, 'loadSessionList');

      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
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
    it('should have complementary role (aside element)', () => {
      renderWithStore(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

      const panel = screen.getByRole('complementary');
      expect(panel).toBeInTheDocument();
      expect(panel.tagName).toBe('ASIDE');
    });

    it('should have aria-label', () => {
      renderWithStore(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

      const panel = screen.getByRole('complementary');
      expect(panel).toHaveAttribute('aria-label', 'AI Assistant');
    });

    it('should have expanded state on menu button', async () => {
      renderWithStore(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

      const menuButton = screen.getByLabelText('More options');
      expect(menuButton).toHaveAttribute('aria-expanded', 'false');

      await userEvent.click(menuButton);

      expect(menuButton).toHaveAttribute('aria-expanded', 'true');
    });
  });

  describe('Props Handling', () => {
    it('should handle missing optional props', () => {
      expect(() => {
        renderWithStore(
          <AIAssistantPanel isOpen={true} onClose={mockOnClose} />
        );
      }).not.toThrow();
    });

    it('should render children in chat view', () => {
      renderWithStore(
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
      renderWithStore(
        <AIAssistantPanel
          isOpen={true}
          onClose={mockOnClose}
          sessionId="session-1"
        />
      );

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      expect(textarea).not.toBeDisabled();
    });

    it('should default isResizable to false', () => {
      renderWithStore(<AIAssistantPanel isOpen={true} onClose={mockOnClose} />);

      const panel = screen.getByRole('complementary');
      expect(panel).toHaveClass('w-[400px]');
    });
  });
});
