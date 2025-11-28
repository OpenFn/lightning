/**
 * SessionList - Tests for AI Assistant session list component
 *
 * Tests the session list with search, sorting, and selection functionality.
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { SessionList } from '../../../js/collaborative-editor/components/SessionList';
import { createAIAssistantStore } from '../../../js/collaborative-editor/stores/createAIAssistantStore';
import { createMockAISession } from '../__helpers__/aiAssistantHelpers';

describe('SessionList', () => {
  let mockStore: ReturnType<typeof createAIAssistantStore>;
  let mockOnSessionSelect: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockStore = createAIAssistantStore();
    mockOnSessionSelect = vi.fn();
    vi.clearAllMocks();
  });

  describe('Empty State', () => {
    it('should show empty state when no sessions', () => {
      render(
        <SessionList
          store={mockStore}
          onSessionSelect={mockOnSessionSelect}
          currentSessionId={null}
        />
      );

      expect(screen.getByText('No sessions yet')).toBeInTheDocument();
      expect(
        screen.getByText(/Start a conversation to see it here/)
      ).toBeInTheDocument();
    });

    it('should show chat bubble icon in empty state', () => {
      const { container } = render(
        <SessionList
          store={mockStore}
          onSessionSelect={mockOnSessionSelect}
          currentSessionId={null}
        />
      );

      expect(
        container.querySelector('.hero-chat-bubble-left-right')
      ).toBeInTheDocument();
    });
  });

  describe('Loading State', () => {
    it('should not show loading spinner when sessions exist', () => {
      const sessions = [createMockAISession({ title: 'Session 1' })];

      mockStore._setSessionList({
        sessions,
        pagination: {
          total_count: 1,
          has_next_page: false,
          has_prev_page: false,
        },
      });

      (mockStore as any).state = {
        ...mockStore.getSnapshot(),
        sessionListLoading: true,
      };

      render(
        <SessionList
          store={mockStore}
          onSessionSelect={mockOnSessionSelect}
          currentSessionId={null}
        />
      );

      expect(screen.queryByText('Loading sessions...')).not.toBeInTheDocument();
      expect(screen.getByText('Session 1')).toBeInTheDocument();
    });
  });

  describe('Session Display', () => {
    it('should render session list', () => {
      const sessions = [
        createMockAISession({ id: '1', title: 'Session 1' }),
        createMockAISession({ id: '2', title: 'Session 2' }),
      ];

      mockStore._setSessionList({
        sessions,
        pagination: {
          total_count: 2,
          has_next_page: false,
          has_prev_page: false,
        },
      });

      render(
        <SessionList
          store={mockStore}
          onSessionSelect={mockOnSessionSelect}
          currentSessionId={null}
        />
      );

      expect(screen.getByText('Session 1')).toBeInTheDocument();
      expect(screen.getByText('Session 2')).toBeInTheDocument();
    });

    it('should call onSessionSelect when session clicked', async () => {
      const sessions = [
        createMockAISession({ id: 'session-1', title: 'Test Session' }),
      ];

      mockStore._setSessionList({
        sessions,
        pagination: {
          total_count: 1,
          has_next_page: false,
          has_prev_page: false,
        },
      });

      render(
        <SessionList
          store={mockStore}
          onSessionSelect={mockOnSessionSelect}
          currentSessionId={null}
        />
      );

      const sessionButton = screen.getByText('Test Session');
      await userEvent.click(sessionButton);

      expect(mockOnSessionSelect).toHaveBeenCalledWith('session-1');
    });

    it('should highlight current session', () => {
      const sessions = [
        createMockAISession({ id: 'session-1', title: 'Active Session' }),
        createMockAISession({ id: 'session-2', title: 'Other Session' }),
      ];

      mockStore._setSessionList({
        sessions,
        pagination: {
          total_count: 2,
          has_next_page: false,
          has_prev_page: false,
        },
      });

      const { container } = render(
        <SessionList
          store={mockStore}
          onSessionSelect={mockOnSessionSelect}
          currentSessionId="session-1"
        />
      );

      // Active session should have special styling (bg-primary or border-primary)
      const activeSession = screen
        .getByText('Active Session')
        .closest('button');
      expect(activeSession?.className).toMatch(/bg-primary|border-primary/);
    });
  });

  describe('Search Functionality', () => {
    beforeEach(() => {
      const sessions = [
        createMockAISession({ id: '1', title: 'Workflow Design' }),
        createMockAISession({ id: '2', title: 'Job Code Help' }),
        createMockAISession({ id: '3', title: 'Debugging Error' }),
      ];

      mockStore._setSessionList({
        sessions,
        pagination: {
          total_count: 3,
          has_next_page: false,
          has_prev_page: false,
        },
      });
    });

    it('should render search input', () => {
      render(
        <SessionList
          store={mockStore}
          onSessionSelect={mockOnSessionSelect}
          currentSessionId={null}
        />
      );

      expect(
        screen.getByPlaceholderText('Search conversations...')
      ).toBeInTheDocument();
    });

    it('should filter sessions by search query', async () => {
      render(
        <SessionList
          store={mockStore}
          onSessionSelect={mockOnSessionSelect}
          currentSessionId={null}
        />
      );

      const searchInput = screen.getByPlaceholderText(
        'Search conversations...'
      );
      await userEvent.type(searchInput, 'workflow');

      await waitFor(() => {
        expect(screen.getByText('Workflow Design')).toBeInTheDocument();
        expect(screen.queryByText('Job Code Help')).not.toBeInTheDocument();
        expect(screen.queryByText('Debugging Error')).not.toBeInTheDocument();
      });
    });

    it('should be case insensitive', async () => {
      render(
        <SessionList
          store={mockStore}
          onSessionSelect={mockOnSessionSelect}
          currentSessionId={null}
        />
      );

      const searchInput = screen.getByPlaceholderText(
        'Search conversations...'
      );
      await userEvent.type(searchInput, 'WORKFLOW');

      await waitFor(() => {
        expect(screen.getByText('Workflow Design')).toBeInTheDocument();
      });
    });

    it('should show clear button when search has text', async () => {
      render(
        <SessionList
          store={mockStore}
          onSessionSelect={mockOnSessionSelect}
          currentSessionId={null}
        />
      );

      const searchInput = screen.getByPlaceholderText(
        'Search conversations...'
      );
      await userEvent.type(searchInput, 'test');

      const clearButton = screen.getByRole('button', { name: /clear search/i });
      expect(clearButton).toBeInTheDocument();
    });

    it('should clear search when clear button clicked', async () => {
      render(
        <SessionList
          store={mockStore}
          onSessionSelect={mockOnSessionSelect}
          currentSessionId={null}
        />
      );

      const searchInput = screen.getByPlaceholderText(
        'Search conversations...'
      ) as HTMLInputElement;
      await userEvent.type(searchInput, 'test');

      expect(searchInput.value).toBe('test');

      const clearButton = screen.getByRole('button', { name: /clear search/i });
      await userEvent.click(clearButton);

      expect(searchInput.value).toBe('');
    });

    it('should show all sessions when search is cleared', async () => {
      render(
        <SessionList
          store={mockStore}
          onSessionSelect={mockOnSessionSelect}
          currentSessionId={null}
        />
      );

      const searchInput = screen.getByPlaceholderText(
        'Search conversations...'
      );
      await userEvent.type(searchInput, 'workflow');

      await waitFor(() => {
        expect(screen.queryByText('Job Code Help')).not.toBeInTheDocument();
      });

      const clearButton = screen.getByRole('button', { name: /clear search/i });
      await userEvent.click(clearButton);

      await waitFor(() => {
        expect(screen.getByText('Workflow Design')).toBeInTheDocument();
        expect(screen.getByText('Job Code Help')).toBeInTheDocument();
        expect(screen.getByText('Debugging Error')).toBeInTheDocument();
      });
    });
  });

  describe('Sort Functionality', () => {
    it('should render sort button', () => {
      const sessions = [createMockAISession({ title: 'Session' })];

      mockStore._setSessionList({
        sessions,
        pagination: {
          total_count: 1,
          has_next_page: false,
          has_prev_page: false,
        },
      });

      const { container } = render(
        <SessionList
          store={mockStore}
          onSessionSelect={mockOnSessionSelect}
          currentSessionId={null}
        />
      );

      // Sort button has "Latest" or "Oldest" text
      expect(screen.getByText(/Latest|Oldest/)).toBeInTheDocument();
    });
  });

  describe('Pagination', () => {
    it('should show load more button when has_next_page is true', () => {
      const sessions = [createMockAISession({ title: 'Session' })];

      mockStore._setSessionList({
        sessions,
        pagination: {
          total_count: 25,
          has_next_page: true,
          has_prev_page: false,
        },
      });

      render(
        <SessionList
          store={mockStore}
          onSessionSelect={mockOnSessionSelect}
          currentSessionId={null}
        />
      );

      expect(
        screen.getByRole('button', { name: /load.*more/i })
      ).toBeInTheDocument();
    });

    it('should not show load more button when has_next_page is false', () => {
      const sessions = [createMockAISession({ title: 'Session' })];

      mockStore._setSessionList({
        sessions,
        pagination: {
          total_count: 1,
          has_next_page: false,
          has_prev_page: false,
        },
      });

      render(
        <SessionList
          store={mockStore}
          onSessionSelect={mockOnSessionSelect}
          currentSessionId={null}
        />
      );

      expect(
        screen.queryByRole('button', { name: /load more/i })
      ).not.toBeInTheDocument();
    });

    it('should call loadSessionList when load more clicked', async () => {
      const loadSpy = vi.spyOn(mockStore, 'loadSessionList');

      const sessions = [createMockAISession({ title: 'Session' })];

      mockStore._setSessionList({
        sessions,
        pagination: {
          total_count: 25,
          has_next_page: true,
          has_prev_page: false,
        },
      });

      render(
        <SessionList
          store={mockStore}
          onSessionSelect={mockOnSessionSelect}
          currentSessionId={null}
        />
      );

      const loadMoreButton = screen.getByRole('button', {
        name: /load.*more/i,
      });
      await userEvent.click(loadMoreButton);

      expect(loadSpy).toHaveBeenCalledWith({
        offset: 1,
        limit: 20,
        append: true,
      });
    });
  });

  describe('Session Metadata', () => {
    it('should show message count', () => {
      const sessions = [
        createMockAISession({ title: 'Session', message_count: 5 }),
      ];

      mockStore._setSessionList({
        sessions,
        pagination: {
          total_count: 1,
          has_next_page: false,
          has_prev_page: false,
        },
      });

      render(
        <SessionList
          store={mockStore}
          onSessionSelect={mockOnSessionSelect}
          currentSessionId={null}
        />
      );

      expect(screen.getByText(/5/)).toBeInTheDocument();
    });
  });
});
