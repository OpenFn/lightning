/**
 * ActiveCollaborators Component Tests
 *
 * Tests for the ActiveCollaborators component that displays circular avatars
 * for remote collaborative users with activity indicators.
 *
 * Test categories:
 * 1. Basic Rendering - Component visibility and avatar count
 * 4. Activity Indicator - Border colors based on lastSeen timestamp
 * 6. Store Integration - Integration with useRemoteUsers hook
 * 7. Edge Cases - Empty states and state transitions
 */

import { render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { ActiveCollaborators } from '../../../js/collaborative-editor/components/ActiveCollaborators';
import type { AwarenessUser } from '../../../js/collaborative-editor/types/awareness';

// Mock the useRemoteUsers hook
let mockRemoteUsers: AwarenessUser[] = [];

vi.mock('../../../js/collaborative-editor/hooks/useAwareness', () => ({
  useRemoteUsers: () => mockRemoteUsers,
}));

/**
 * Creates a mock AwarenessUser with sensible defaults
 */
function createMockAwarenessUser(
  overrides: Partial<AwarenessUser> = {}
): AwarenessUser {
  return {
    clientId: Math.floor(Math.random() * 1000000),
    user: {
      id: `user-${Math.random().toString(36).substring(7)}`,
      name: 'John Doe',
      email: 'john@example.com',
      color: '#ff0000',
    },
    lastSeen: Date.now(),
    ...overrides,
  };
}

describe('ActiveCollaborators - Basic Rendering', () => {
  beforeEach(() => {
    mockRemoteUsers = [];
  });

  test('renders nothing when there are no remote users', () => {
    mockRemoteUsers = [];

    const { container } = render(<ActiveCollaborators />);

    expect(container.firstChild).toBeNull();
  });

  test('renders avatars for remote users', () => {
    mockRemoteUsers = [
      createMockAwarenessUser({
        user: {
          id: 'user-1',
          name: 'John Doe',
          email: 'john@example.com',
          color: '#ff0000',
        },
      }),
      createMockAwarenessUser({
        user: {
          id: 'user-2',
          name: 'Jane Smith',
          email: 'jane@example.com',
          color: '#00ff00',
        },
      }),
    ];

    const { container } = render(<ActiveCollaborators />);

    expect(container.firstChild).not.toBeNull();
    expect(screen.getByText('JD')).toBeInTheDocument();
    expect(screen.getByText('JS')).toBeInTheDocument();
  });

  test('renders correct number of avatars matching remote users count', () => {
    mockRemoteUsers = [
      createMockAwarenessUser({
        user: {
          id: 'user-1',
          name: 'Alice Anderson',
          email: 'alice@example.com',
          color: '#ff0000',
        },
      }),
      createMockAwarenessUser({
        user: {
          id: 'user-2',
          name: 'Bob Brown',
          email: 'bob@example.com',
          color: '#00ff00',
        },
      }),
      createMockAwarenessUser({
        user: {
          id: 'user-3',
          name: 'Charlie Chen',
          email: 'charlie@example.com',
          color: '#0000ff',
        },
      }),
    ];

    render(<ActiveCollaborators />);

    expect(screen.getByText('AA')).toBeInTheDocument();
    expect(screen.getByText('BB')).toBeInTheDocument();
    expect(screen.getByText('CC')).toBeInTheDocument();
  });

  test('renders correct initials for single-word names', () => {
    mockRemoteUsers = [
      createMockAwarenessUser({
        user: {
          id: 'user-1',
          name: 'Madonna',
          email: 'madonna@example.com',
          color: '#ff0000',
        },
      }),
    ];

    render(<ActiveCollaborators />);

    // Single-word name should result in "??" (no last name)
    expect(screen.getByText('??')).toBeInTheDocument();
  });

  test('renders correct initials for multi-part names (uses first and last parts)', () => {
    mockRemoteUsers = [
      createMockAwarenessUser({
        user: {
          id: 'user-1',
          name: 'Mary Jane Watson Parker',
          email: 'mary@example.com',
          color: '#ff0000',
        },
      }),
    ];

    render(<ActiveCollaborators />);

    // Should use first part "Mary" and last part "Parker"
    expect(screen.getByText('MP')).toBeInTheDocument();
  });
});

describe('ActiveCollaborators - Activity Indicator', () => {
  beforeEach(() => {
    mockRemoteUsers = [];
  });

  test('shows green border for users active within last 2 minutes', () => {
    const now = Date.now();
    const oneMinuteAgo = now - 60 * 1000; // 1 minute ago

    mockRemoteUsers = [
      createMockAwarenessUser({
        user: {
          id: 'user-1',
          name: 'John Doe',
          email: 'john@example.com',
          color: '#ff0000',
        },
        lastSeen: oneMinuteAgo,
      }),
    ];

    const { container } = render(<ActiveCollaborators />);

    const borderDiv = container.querySelector('.border-green-500');
    expect(borderDiv).toBeInTheDocument();
  });

  test('shows gray border for users inactive for more than 2 minutes', () => {
    const now = Date.now();
    const threeMinutesAgo = now - 3 * 60 * 1000; // 3 minutes ago

    mockRemoteUsers = [
      createMockAwarenessUser({
        user: {
          id: 'user-1',
          name: 'John Doe',
          email: 'john@example.com',
          color: '#ff0000',
        },
        lastSeen: threeMinutesAgo,
      }),
    ];

    const { container } = render(<ActiveCollaborators />);

    const borderDiv = container.querySelector('.border-gray-500');
    expect(borderDiv).toBeInTheDocument();
  });

  test('shows gray border when lastSeen is undefined', () => {
    mockRemoteUsers = [
      createMockAwarenessUser({
        user: {
          id: 'user-1',
          name: 'John Doe',
          email: 'john@example.com',
          color: '#ff0000',
        },
        lastSeen: undefined,
      }),
    ];

    const { container } = render(<ActiveCollaborators />);

    const borderDiv = container.querySelector('.border-gray-500');
    expect(borderDiv).toBeInTheDocument();
  });

  test('correctly implements the 2-minute threshold (120,000ms)', () => {
    const now = Date.now();
    const justUnderTwoMinutes = now - (2 * 60 * 1000 - 1000); // 1 second before threshold
    const justOverTwoMinutes = now - (2 * 60 * 1000 + 1000); // 1 second after threshold

    // User just under 2 minutes should have green border
    mockRemoteUsers = [
      createMockAwarenessUser({
        clientId: 1,
        user: {
          id: 'user-1',
          name: 'Active User',
          email: 'active@example.com',
          color: '#ff0000',
        },
        lastSeen: justUnderTwoMinutes,
      }),
      createMockAwarenessUser({
        clientId: 2,
        user: {
          id: 'user-2',
          name: 'Inactive User',
          email: 'inactive@example.com',
          color: '#00ff00',
        },
        lastSeen: justOverTwoMinutes,
      }),
    ];

    const { container } = render(<ActiveCollaborators />);

    const greenBorder = container.querySelector('.border-green-500');
    const grayBorder = container.querySelector('.border-gray-500');

    expect(greenBorder).toBeInTheDocument();
    expect(grayBorder).toBeInTheDocument();
  });

  test('border color updates when user crosses the 2-minute threshold', () => {
    vi.useFakeTimers();
    const now = Date.now();

    mockRemoteUsers = [
      createMockAwarenessUser({
        user: {
          id: 'user-1',
          name: 'John Doe',
          email: 'john@example.com',
          color: '#ff0000',
        },
        lastSeen: now,
      }),
    ];

    const { container, rerender } = render(<ActiveCollaborators />);

    // Initially should have green border
    expect(container.querySelector('.border-green-500')).toBeInTheDocument();

    // Advance time by 3 minutes
    vi.advanceTimersByTime(3 * 60 * 1000);

    // Re-render to trigger the component to re-evaluate
    rerender(<ActiveCollaborators />);

    // Now should have gray border
    expect(container.querySelector('.border-gray-500')).toBeInTheDocument();

    vi.useRealTimers();
  });
});

describe('ActiveCollaborators - Store Integration', () => {
  beforeEach(() => {
    mockRemoteUsers = [];
  });

  test('uses useRemoteUsers hook correctly (excludes local user)', () => {
    // The hook should already filter out local users, so we only set remote users
    mockRemoteUsers = [
      createMockAwarenessUser({
        user: {
          id: 'remote-user',
          name: 'Remote User',
          email: 'remote@example.com',
          color: '#00ff00',
        },
      }),
    ];

    render(<ActiveCollaborators />);

    // Should show remote user
    expect(screen.getByText('RU')).toBeInTheDocument();
  });

  test('updates when awareness state changes (users join)', () => {
    mockRemoteUsers = [];

    const { rerender } = render(<ActiveCollaborators />);

    // Initially no users
    expect(screen.queryByText('JD')).not.toBeInTheDocument();

    // Add a user
    mockRemoteUsers = [
      createMockAwarenessUser({
        user: {
          id: 'user-1',
          name: 'John Doe',
          email: 'john@example.com',
          color: '#ff0000',
        },
      }),
    ];

    rerender(<ActiveCollaborators />);

    // User should now appear
    expect(screen.getByText('JD')).toBeInTheDocument();
  });

  test('updates when awareness state changes (users leave)', () => {
    mockRemoteUsers = [
      createMockAwarenessUser({
        user: {
          id: 'user-1',
          name: 'John Doe',
          email: 'john@example.com',
          color: '#ff0000',
        },
      }),
    ];

    const { rerender } = render(<ActiveCollaborators />);

    // User should be visible
    expect(screen.getByText('JD')).toBeInTheDocument();

    // Remove user
    mockRemoteUsers = [];
    rerender(<ActiveCollaborators />);

    // User should no longer be visible
    expect(screen.queryByText('JD')).not.toBeInTheDocument();
  });

  test('handles empty users array gracefully', () => {
    mockRemoteUsers = [];

    const { container } = render(<ActiveCollaborators />);

    expect(container.firstChild).toBeNull();
  });
});

describe('ActiveCollaborators - Edge Cases', () => {
  beforeEach(() => {
    mockRemoteUsers = [];
  });

  test('transitions from showing avatars to null when all users leave', () => {
    mockRemoteUsers = [
      createMockAwarenessUser({
        user: {
          id: 'user-1',
          name: 'John Doe',
          email: 'john@example.com',
          color: '#ff0000',
        },
      }),
      createMockAwarenessUser({
        user: {
          id: 'user-2',
          name: 'Jane Smith',
          email: 'jane@example.com',
          color: '#00ff00',
        },
      }),
    ];

    const { container, rerender } = render(<ActiveCollaborators />);

    // Should show users
    expect(screen.getByText('JD')).toBeInTheDocument();
    expect(screen.getByText('JS')).toBeInTheDocument();

    // All users leave
    mockRemoteUsers = [];
    rerender(<ActiveCollaborators />);

    // Should render null
    expect(container.firstChild).toBeNull();
  });

  test('handles multiple users with similar names', () => {
    mockRemoteUsers = [
      createMockAwarenessUser({
        clientId: 1,
        user: {
          id: 'user-1',
          name: 'John Doe',
          email: 'john1@example.com',
          color: '#ff0000',
        },
      }),
      createMockAwarenessUser({
        clientId: 2,
        user: {
          id: 'user-2',
          name: 'John Doe',
          email: 'john2@example.com',
          color: '#00ff00',
        },
      }),
      createMockAwarenessUser({
        clientId: 3,
        user: {
          id: 'user-3',
          name: 'Jane Doe',
          email: 'jane@example.com',
          color: '#0000ff',
        },
      }),
    ];

    render(<ActiveCollaborators />);

    // All three should render (React will handle duplicate text content)
    const jdElements = screen.getAllByText('JD');
    expect(jdElements).toHaveLength(3); // 2 John Doe + 1 Jane Doe
  });

  test('handles user with undefined lastSeen timestamp', () => {
    mockRemoteUsers = [
      createMockAwarenessUser({
        user: {
          id: 'user-1',
          name: 'John Doe',
          email: 'john@example.com',
          color: '#ff0000',
        },
        lastSeen: undefined,
      }),
    ];

    const { container } = render(<ActiveCollaborators />);

    // Should render without crashing
    expect(screen.getByText('JD')).toBeInTheDocument();
    // Should have gray border (inactive)
    expect(container.querySelector('.border-gray-500')).toBeInTheDocument();
  });

  test('handles rapidly changing awareness states', () => {
    const user1 = createMockAwarenessUser({
      user: {
        id: 'user-1',
        name: 'John Doe',
        email: 'john@example.com',
        color: '#ff0000',
      },
    });
    const user2 = createMockAwarenessUser({
      user: {
        id: 'user-2',
        name: 'Jane Smith',
        email: 'jane@example.com',
        color: '#00ff00',
      },
    });
    const user3 = createMockAwarenessUser({
      user: {
        id: 'user-3',
        name: 'Bob Brown',
        email: 'bob@example.com',
        color: '#0000ff',
      },
    });

    const { rerender } = render(<ActiveCollaborators />);

    // Rapid state changes
    mockRemoteUsers = [user1];
    rerender(<ActiveCollaborators />);
    expect(screen.getByText('JD')).toBeInTheDocument();

    mockRemoteUsers = [user1, user2];
    rerender(<ActiveCollaborators />);
    expect(screen.getByText('JD')).toBeInTheDocument();
    expect(screen.getByText('JS')).toBeInTheDocument();

    mockRemoteUsers = [user2, user3];
    rerender(<ActiveCollaborators />);
    expect(screen.queryByText('JD')).not.toBeInTheDocument();
    expect(screen.getByText('JS')).toBeInTheDocument();
    expect(screen.getByText('BB')).toBeInTheDocument();

    mockRemoteUsers = [];
    rerender(<ActiveCollaborators />);
    expect(screen.queryByText('JS')).not.toBeInTheDocument();
    expect(screen.queryByText('BB')).not.toBeInTheDocument();
  });

  test('handles empty name strings', () => {
    mockRemoteUsers = [
      createMockAwarenessUser({
        user: {
          id: 'user-1',
          name: '',
          email: 'empty@example.com',
          color: '#ff0000',
        },
      }),
    ];

    render(<ActiveCollaborators />);

    // Should show fallback "??"
    expect(screen.getByText('??')).toBeInTheDocument();
  });

  test('handles names with only whitespace', () => {
    mockRemoteUsers = [
      createMockAwarenessUser({
        user: {
          id: 'user-1',
          name: '   ',
          email: 'whitespace@example.com',
          color: '#ff0000',
        },
      }),
    ];

    render(<ActiveCollaborators />);

    // Should show fallback "??" because trimmed name parts are empty
    expect(screen.getByText('??')).toBeInTheDocument();
  });
});
