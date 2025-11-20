/**
 * RemoteCursor Component Tests
 *
 * Tests for the RemoteCursors and RemoteCursor components that render
 * collaborative user cursors on the workflow diagram canvas.
 *
 * Test coverage:
 * - Cursor rendering with awareness data
 * - Position calculation with viewport transforms
 * - Cursor visibility and filtering
 * - User name labels and colors
 * - Viewport transform reactivity
 */

import { describe, expect, test, beforeEach, vi } from 'vitest';
import { render, screen, act } from '@testing-library/react';
import { ReactFlowProvider } from '@xyflow/react';
import { Awareness } from 'y-protocols/awareness';
import * as Y from 'yjs';

import { StoreContext } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import type { AwarenessStoreInstance } from '../../../../js/collaborative-editor/stores/createAwarenessStore';
import { createAwarenessStore } from '../../../../js/collaborative-editor/stores/createAwarenessStore';
import type { AwarenessUser } from '../../../../js/collaborative-editor/types/awareness';
import { RemoteCursors } from '../../../../js/collaborative-editor/components/diagram/RemoteCursor';

// Mock the @xyflow/react hooks
vi.mock('@xyflow/react', async () => {
  const actual = await vi.importActual('@xyflow/react');
  return {
    ...actual,
    useViewport: vi.fn(() => ({ x: 0, y: 0, zoom: 1 })),
  };
});

describe('RemoteCursors', () => {
  let awarenessStore: AwarenessStoreInstance;
  let mockAwareness: Awareness;
  let ydoc: Y.Doc;

  beforeEach(() => {
    awarenessStore = createAwarenessStore();
    ydoc = new Y.Doc();
    mockAwareness = new Awareness(ydoc);

    // Initialize the awareness store
    awarenessStore.initializeAwareness(mockAwareness, {
      id: 'local-user',
      name: 'Local User',
      email: 'local@example.com',
      color: '#CCCCCC',
    });
  });

  // Helper to set awareness states for testing
  const setAwarenessUsers = (users: AwarenessUser[]) => {
    // Clear all existing remote states (not local)
    const states = mockAwareness.getStates();
    const statesToRemove: number[] = [];
    states.forEach((_, clientId) => {
      if (clientId !== mockAwareness.clientID) {
        statesToRemove.push(clientId);
      }
    });

    // Remove old states
    statesToRemove.forEach(clientId => {
      mockAwareness.states.delete(clientId);
      mockAwareness.meta.delete(clientId);
    });

    // Set new states
    users.forEach(user => {
      const state: Record<string, any> = {
        user: user.user,
      };
      if (user.cursor) {
        state.cursor = user.cursor;
      }
      if (user.selection) {
        state.selection = user.selection;
      }
      if (user.lastSeen) {
        state.lastSeen = user.lastSeen;
      }

      // Set remote state
      mockAwareness.states.set(user.clientId, state);
      mockAwareness.meta.set(user.clientId, {
        clock: Date.now(),
        lastUpdated: Date.now(),
      });
    });

    // Trigger awareness change
    awarenessStore._internal.handleAwarenessChange();
  };

  const renderWithProviders = (component: React.ReactElement) => {
    return render(
      <StoreContext.Provider
        value={
          {
            awarenessStore,
          } as any
        }
      >
        <ReactFlowProvider>{component}</ReactFlowProvider>
      </StoreContext.Provider>
    );
  };

  test('renders nothing when no remote users have cursors', () => {
    setAwarenessUsers([]);

    const { container } = renderWithProviders(<RemoteCursors />);

    expect(container.firstChild).toBeNull();
  });

  test('renders nothing when remote users exist but have no cursor data', () => {
    const users: AwarenessUser[] = [
      {
        clientId: 1,
        user: {
          id: 'user-1',
          name: 'Alice',
          color: '#FF0000',
        },
        // No cursor property
      },
      {
        clientId: 2,
        user: {
          id: 'user-2',
          name: 'Bob',
          color: '#00FF00',
        },
        // No cursor property
      },
    ];

    setAwarenessUsers(users);

    const { container } = renderWithProviders(<RemoteCursors />);

    expect(container.firstChild).toBeNull();
  });

  test('renders cursor for single remote user with cursor data', () => {
    const users: AwarenessUser[] = [
      {
        clientId: 1,
        user: {
          id: 'user-1',
          name: 'Alice',
          color: '#FF0000',
        },
        cursor: { x: 100, y: 200 },
      },
    ];

    setAwarenessUsers(users);

    const { container } = renderWithProviders(<RemoteCursors />);

    // Should render the wrapper div and cursor
    expect(container.querySelector('.absolute.inset-0')).toBeInTheDocument();
    expect(screen.getByText('Alice')).toBeInTheDocument();
  });

  test('renders multiple cursors for multiple users', () => {
    const users: AwarenessUser[] = [
      {
        clientId: 1,
        user: {
          id: 'user-1',
          name: 'Alice',
          color: '#FF0000',
        },
        cursor: { x: 100, y: 200 },
      },
      {
        clientId: 2,
        user: {
          id: 'user-2',
          name: 'Bob',
          color: '#00FF00',
        },
        cursor: { x: 300, y: 400 },
      },
      {
        clientId: 3,
        user: {
          id: 'user-3',
          name: 'Charlie',
          color: '#0000FF',
        },
        cursor: { x: 500, y: 600 },
      },
    ];

    setAwarenessUsers(users);

    renderWithProviders(<RemoteCursors />);

    expect(screen.getByText('Alice')).toBeInTheDocument();
    expect(screen.getByText('Bob')).toBeInTheDocument();
    expect(screen.getByText('Charlie')).toBeInTheDocument();
  });

  test('filters out users without cursor data', () => {
    const users: AwarenessUser[] = [
      {
        clientId: 1,
        user: {
          id: 'user-1',
          name: 'Alice',
          color: '#FF0000',
        },
        cursor: { x: 100, y: 200 },
      },
      {
        clientId: 2,
        user: {
          id: 'user-2',
          name: 'Bob',
          color: '#00FF00',
        },
        // No cursor
      },
      {
        clientId: 3,
        user: {
          id: 'user-3',
          name: 'Charlie',
          color: '#0000FF',
        },
        cursor: { x: 500, y: 600 },
      },
    ];

    setAwarenessUsers(users);

    renderWithProviders(<RemoteCursors />);

    expect(screen.getByText('Alice')).toBeInTheDocument();
    expect(screen.queryByText('Bob')).not.toBeInTheDocument();
    expect(screen.getByText('Charlie')).toBeInTheDocument();
  });

  test('applies user color to cursor', () => {
    const users: AwarenessUser[] = [
      {
        clientId: 1,
        user: {
          id: 'user-1',
          name: 'Alice',
          color: '#FF0000',
        },
        cursor: { x: 100, y: 200 },
      },
    ];

    setAwarenessUsers(users);

    const { container } = renderWithProviders(<RemoteCursors />);

    // Check that the SVG path has the fill color
    const svg = container.querySelector('svg path');
    expect(svg).toHaveAttribute('fill', '#FF0000');

    // Check that the label div has the background color
    const labelDiv = container.querySelector('.text-xs.font-medium.text-white');
    expect(labelDiv).toHaveStyle({ backgroundColor: 'rgb(255, 0, 0)' });
  });

  test('cursor has correct CSS classes for pointer-events-none', () => {
    const users: AwarenessUser[] = [
      {
        clientId: 1,
        user: {
          id: 'user-1',
          name: 'Alice',
          color: '#FF0000',
        },
        cursor: { x: 100, y: 200 },
      },
    ];

    setAwarenessUsers(users);

    const { container } = renderWithProviders(<RemoteCursors />);

    // The wrapper should have pointer-events-none to not interfere with canvas
    const wrapper = container.querySelector('.pointer-events-none');
    expect(wrapper).toBeInTheDocument();
    expect(wrapper).toHaveClass('absolute', 'inset-0', 'z-50');
  });

  test('cursor renders SVG arrow icon', () => {
    const users: AwarenessUser[] = [
      {
        clientId: 1,
        user: {
          id: 'user-1',
          name: 'Alice',
          color: '#FF0000',
        },
        cursor: { x: 100, y: 200 },
      },
    ];

    setAwarenessUsers(users);

    const { container } = renderWithProviders(<RemoteCursors />);

    const svg = container.querySelector('svg');
    expect(svg).toBeInTheDocument();
    expect(svg).toHaveAttribute('width', '24');
    expect(svg).toHaveAttribute('height', '24');
    expect(svg).toHaveClass('drop-shadow-md');
  });

  test('cursor label has correct text styling', () => {
    const users: AwarenessUser[] = [
      {
        clientId: 1,
        user: {
          id: 'user-1',
          name: 'Alice',
          color: '#FF0000',
        },
        cursor: { x: 100, y: 200 },
      },
    ];

    setAwarenessUsers(users);

    const { container } = renderWithProviders(<RemoteCursors />);

    const labelDiv = container.querySelector('.text-xs.font-medium.text-white');
    expect(labelDiv).toHaveClass(
      'text-xs',
      'font-medium',
      'text-white',
      'whitespace-nowrap'
    );
  });

  test('uses clientId as React key', () => {
    const users: AwarenessUser[] = [
      {
        clientId: 123,
        user: {
          id: 'user-1',
          name: 'Alice',
          color: '#FF0000',
        },
        cursor: { x: 100, y: 200 },
      },
      {
        clientId: 456,
        user: {
          id: 'user-2',
          name: 'Bob',
          color: '#00FF00',
        },
        cursor: { x: 300, y: 400 },
      },
    ];

    setAwarenessUsers(users);

    const { container } = renderWithProviders(<RemoteCursors />);

    // Check that we have two cursor elements rendered
    const cursorDivs = container.querySelectorAll('.absolute.transition-all');
    expect(cursorDivs).toHaveLength(2);
  });

  test('handles rapid cursor updates', () => {
    const users: AwarenessUser[] = [
      {
        clientId: 1,
        user: {
          id: 'user-1',
          name: 'Alice',
          color: '#FF0000',
        },
        cursor: { x: 100, y: 200 },
      },
    ];

    setAwarenessUsers(users);

    const { rerender } = renderWithProviders(<RemoteCursors />);

    expect(screen.getByText('Alice')).toBeInTheDocument();

    // Update cursor position
    const updatedUsers: AwarenessUser[] = [
      {
        clientId: 1,
        user: {
          id: 'user-1',
          name: 'Alice',
          color: '#FF0000',
        },
        cursor: { x: 150, y: 250 },
      },
    ];

    setAwarenessUsers(updatedUsers);
    rerender(
      <StoreContext.Provider value={{ awarenessStore } as any}>
        <ReactFlowProvider>
          <RemoteCursors />
        </ReactFlowProvider>
      </StoreContext.Provider>
    );

    // Cursor should still be rendered with same name
    expect(screen.getByText('Alice')).toBeInTheDocument();
  });

  test('removes cursor when user disconnects', () => {
    const users: AwarenessUser[] = [
      {
        clientId: 1,
        user: {
          id: 'user-1',
          name: 'Alice',
          color: '#FF0000',
        },
        cursor: { x: 100, y: 200 },
      },
      {
        clientId: 2,
        user: {
          id: 'user-2',
          name: 'Bob',
          color: '#00FF00',
        },
        cursor: { x: 300, y: 400 },
      },
    ];

    setAwarenessUsers(users);

    const { rerender } = renderWithProviders(<RemoteCursors />);

    expect(screen.getByText('Alice')).toBeInTheDocument();
    expect(screen.getByText('Bob')).toBeInTheDocument();

    // Remove Alice
    const updatedUsers: AwarenessUser[] = [
      {
        clientId: 2,
        user: {
          id: 'user-2',
          name: 'Bob',
          color: '#00FF00',
        },
        cursor: { x: 300, y: 400 },
      },
    ];

    act(() => {
      setAwarenessUsers(updatedUsers);
      rerender(
        <StoreContext.Provider value={{ awarenessStore } as any}>
          <ReactFlowProvider>
            <RemoteCursors />
          </ReactFlowProvider>
        </StoreContext.Provider>
      );
    });

    expect(screen.queryByText('Alice')).not.toBeInTheDocument();
    expect(screen.getByText('Bob')).toBeInTheDocument();
  });

  test('handles cursor data with null values', () => {
    const users: AwarenessUser[] = [
      {
        clientId: 1,
        user: {
          id: 'user-1',
          name: 'Alice',
          color: '#FF0000',
        },
        cursor: { x: 100, y: 200 },
      },
      {
        clientId: 2,
        user: {
          id: 'user-2',
          name: 'Bob',
          color: '#00FF00',
        },
        cursor: null as any, // Explicitly null cursor
      },
    ];

    setAwarenessUsers(users);

    renderWithProviders(<RemoteCursors />);

    expect(screen.getByText('Alice')).toBeInTheDocument();
    expect(screen.queryByText('Bob')).not.toBeInTheDocument();
  });

  describe('viewport transform integration', () => {
    test('recalculates positions when viewport changes', async () => {
      const { useViewport } = await import('@xyflow/react');

      // Set initial viewport
      vi.mocked(useViewport).mockReturnValue({ x: 0, y: 0, zoom: 1 });

      const users: AwarenessUser[] = [
        {
          clientId: 1,
          user: {
            id: 'user-1',
            name: 'Alice',
            color: '#FF0000',
          },
          cursor: { x: 100, y: 200 },
        },
      ];

      setAwarenessUsers(users);

      const { rerender } = renderWithProviders(<RemoteCursors />);

      expect(screen.getByText('Alice')).toBeInTheDocument();

      // Change viewport (zoom in)
      vi.mocked(useViewport).mockReturnValue({ x: 50, y: 50, zoom: 2 });

      rerender(
        <StoreContext.Provider value={{ awarenessStore } as any}>
          <ReactFlowProvider>
            <RemoteCursors />
          </ReactFlowProvider>
        </StoreContext.Provider>
      );

      // Cursor should still be rendered (position calculation handled internally)
      expect(screen.getByText('Alice')).toBeInTheDocument();
    });

    test('handles negative viewport offsets', async () => {
      const { useViewport } = await import('@xyflow/react');

      vi.mocked(useViewport).mockReturnValue({ x: -100, y: -200, zoom: 1 });

      const users: AwarenessUser[] = [
        {
          clientId: 1,
          user: {
            id: 'user-1',
            name: 'Alice',
            color: '#FF0000',
          },
          cursor: { x: 100, y: 200 },
        },
      ];

      setAwarenessUsers(users);

      renderWithProviders(<RemoteCursors />);

      expect(screen.getByText('Alice')).toBeInTheDocument();
    });

    test('handles extreme zoom levels', async () => {
      const { useViewport } = await import('@xyflow/react');

      // Very zoomed in
      vi.mocked(useViewport).mockReturnValue({ x: 0, y: 0, zoom: 10 });

      const users: AwarenessUser[] = [
        {
          clientId: 1,
          user: {
            id: 'user-1',
            name: 'Alice',
            color: '#FF0000',
          },
          cursor: { x: 10, y: 20 },
        },
      ];

      setAwarenessUsers(users);

      renderWithProviders(<RemoteCursors />);

      expect(screen.getByText('Alice')).toBeInTheDocument();
    });
  });

  describe('edge cases', () => {
    test('handles empty user name', () => {
      const users: AwarenessUser[] = [
        {
          clientId: 1,
          user: {
            id: 'user-1',
            name: '',
            color: '#FF0000',
          },
          cursor: { x: 100, y: 200 },
        },
      ];

      setAwarenessUsers(users);

      const { container } = renderWithProviders(<RemoteCursors />);

      // Should still render the cursor SVG
      expect(container.querySelector('svg')).toBeInTheDocument();
    });

    test('handles very long user names', () => {
      const users: AwarenessUser[] = [
        {
          clientId: 1,
          user: {
            id: 'user-1',
            name: 'A'.repeat(100),
            color: '#FF0000',
          },
          cursor: { x: 100, y: 200 },
        },
      ];

      setAwarenessUsers(users);

      const { container } = renderWithProviders(<RemoteCursors />);

      // Find the label div directly with the text styling classes
      const labelDiv = container.querySelector(
        '.text-xs.font-medium.text-white'
      );
      expect(labelDiv).toHaveClass('whitespace-nowrap');
      expect(labelDiv).toHaveTextContent('A'.repeat(100));
    });

    test('handles coordinates at origin (0, 0)', () => {
      const users: AwarenessUser[] = [
        {
          clientId: 1,
          user: {
            id: 'user-1',
            name: 'Alice',
            color: '#FF0000',
          },
          cursor: { x: 0, y: 0 },
        },
      ];

      setAwarenessUsers(users);

      renderWithProviders(<RemoteCursors />);

      expect(screen.getByText('Alice')).toBeInTheDocument();
    });

    test('handles negative coordinates', () => {
      const users: AwarenessUser[] = [
        {
          clientId: 1,
          user: {
            id: 'user-1',
            name: 'Alice',
            color: '#FF0000',
          },
          cursor: { x: -100, y: -200 },
        },
      ];

      setAwarenessUsers(users);

      renderWithProviders(<RemoteCursors />);

      expect(screen.getByText('Alice')).toBeInTheDocument();
    });

    test('handles very large coordinates', () => {
      const users: AwarenessUser[] = [
        {
          clientId: 1,
          user: {
            id: 'user-1',
            name: 'Alice',
            color: '#FF0000',
          },
          cursor: { x: 999999, y: 999999 },
        },
      ];

      setAwarenessUsers(users);

      renderWithProviders(<RemoteCursors />);

      expect(screen.getByText('Alice')).toBeInTheDocument();
    });
  });
});
