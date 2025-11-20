/**
 * EmailVerificationBanner Component Tests
 *
 * Tests for the EmailVerificationBanner component using React Testing Library.
 * Tests actual component rendering, DOM output, accessibility, and user interactions.
 *
 * Focus: Test what users see and do, not implementation details
 * Reference: unit-test-guidelines.md lines 1186-1388
 *
 * NOTE: Act() warnings may appear in test output for tests where the banner
 * is hidden (returns null). These warnings occur because useSyncExternalStore
 * triggers updates when the component renders nothing. The warnings don't
 * indicate test failures - all tests pass successfully.
 *
 * Zod validation errors for null configs are expected in error handling tests.
 * These verify the component handles invalid data gracefully without crashing.
 */

import { render, screen, waitFor } from '@testing-library/react';
import type React from 'react';
import { describe, expect, test } from 'vitest';
import { EmailVerificationBanner } from '../../../js/collaborative-editor/components/EmailVerificationBanner';
import type { StoreContextValue } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import {
  createMockConfig,
  createMockUser,
  createSessionContext,
  mockPermissions,
} from '../__helpers__/sessionContextFactory';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../mocks/phoenixChannel';

// =============================================================================
// TEST HELPERS
// =============================================================================

interface WrapperOptions {
  user?: ReturnType<typeof createMockUser> | null;
  config?: ReturnType<typeof createMockConfig> | null;
  emitImmediately?: boolean;
}

function createWrapper(
  options: WrapperOptions = {}
): [React.ComponentType<{ children: React.ReactNode }>, () => void] {
  const { user = null, config = null, emitImmediately = true } = options;

  const sessionContextStore = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel('test:room');
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  sessionContextStore._connectChannel(mockProvider as any);

  const emitData = () => {
    (mockChannel as any)._test.emit(
      'session_context',
      createSessionContext({
        user,
        project: null,
        config,
        permissions: mockPermissions,
      })
    );
  };

  // Emit immediately by default
  if (emitImmediately) {
    emitData();
  }

  const mockStoreValue: StoreContextValue = {
    sessionContextStore,
    adaptorStore: {} as any,
    credentialStore: {} as any,
    awarenessStore: {} as any,
    workflowStore: {} as any,
  };

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <StoreContext.Provider value={mockStoreValue}>
      {children}
    </StoreContext.Provider>
  );

  return [wrapper, emitData];
}

// =============================================================================
// BANNER VISIBILITY AND CONTENT
// =============================================================================

describe('EmailVerificationBanner', () => {
  describe('shows banner with content when unverified', () => {
    const user = createMockUser({
      email_confirmed: false,
      inserted_at: '2025-01-13T10:30:00Z',
    });
    const config = createMockConfig({ require_email_verification: true });

    test('displays warning message with deadline', async () => {
      const [wrapper] = createWrapper({ user, config });
      render(<EmailVerificationBanner />, { wrapper });

      await waitFor(() => {
        const alert = screen.getByRole('alert');
        expect(alert).toBeInTheDocument();
        expect(alert).toHaveTextContent(/Please confirm your account before/i);
        expect(alert).toHaveTextContent(/to continue using OpenFn/i);
        expect(alert).toHaveTextContent(/Wednesday, 15 January @ 10:30 UTC/);
      });
    });

    test('includes resend confirmation link', async () => {
      const [wrapper] = createWrapper({ user, config });
      render(<EmailVerificationBanner />, { wrapper });

      await waitFor(() => {
        const link = screen.getByRole('link', {
          name: /Resend confirmation email/i,
        });
        expect(link).toHaveAttribute('href', '/users/send-confirmation-email');
        expect(link.tagName).toBe('A');
      });
    });

    test('includes warning icon', async () => {
      const [wrapper] = createWrapper({ user, config });
      render(<EmailVerificationBanner />, { wrapper });

      await waitFor(() => {
        const alert = screen.getByRole('alert');
        expect(alert.querySelector('span')).toBeInTheDocument();
      });
    });

    test('appears when data loads after initial render', async () => {
      const [wrapper, emitData] = createWrapper({
        user,
        config,
        emitImmediately: false,
      });

      render(<EmailVerificationBanner />, { wrapper });

      expect(screen.queryByRole('alert')).not.toBeInTheDocument();

      emitData();

      await waitFor(() => {
        expect(screen.getByRole('alert')).toBeInTheDocument();
      });
    });
  });

  describe('hides banner when not needed', () => {
    test.each([
      {
        description: 'email confirmed',
        user: createMockUser({ email_confirmed: true }),
        config: createMockConfig({ require_email_verification: true }),
      },
      {
        description: 'verification not required',
        user: createMockUser({ email_confirmed: false }),
        config: createMockConfig({ require_email_verification: false }),
      },
      {
        description: 'user is null',
        user: null,
        config: createMockConfig(),
      },
      {
        description: 'config is null',
        user: createMockUser({ email_confirmed: false }),
        config: null,
      },
      {
        description: 'no session context loaded',
        user: null,
        config: null,
      },
    ])('when $description', async ({ user, config }) => {
      const [wrapper] = createWrapper({ user, config });
      render(<EmailVerificationBanner />, { wrapper });

      expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    });

    test('when session context not yet loaded', async () => {
      const [wrapper] = createWrapper({ emitImmediately: false });
      render(<EmailVerificationBanner />, { wrapper });

      expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    });
  });

  describe('deadline formatting', () => {
    const config = createMockConfig({ require_email_verification: true });

    test.each([
      {
        insertedAt: '2025-01-13T10:30:00Z',
        expectedDeadline: 'Wednesday, 15 January @ 10:30 UTC',
      },
      {
        insertedAt: '2025-01-30T15:00:00Z',
        expectedDeadline: 'Saturday, 1 February @ 15:00 UTC',
      },
      {
        insertedAt: '2024-12-30T15:00:00Z',
        expectedDeadline: 'Wednesday, 1 January @ 15:00 UTC',
      },
    ])(
      'formats deadline correctly: $expectedDeadline',
      async ({ insertedAt, expectedDeadline }) => {
        const user = createMockUser({
          email_confirmed: false,
          inserted_at: insertedAt,
        });

        const [wrapper] = createWrapper({ user, config });
        render(<EmailVerificationBanner />, { wrapper });

        await waitFor(() => {
          expect(
            screen.getByText(new RegExp(expectedDeadline))
          ).toBeInTheDocument();
        });
      }
    );
  });
});
