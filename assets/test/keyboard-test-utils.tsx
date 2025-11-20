/**
 * Test utilities for keyboard shortcut testing
 *
 * These utilities provide library-agnostic helpers for testing keyboard
 * shortcuts. They test user-facing behavior rather than implementation
 * details, ensuring tests remain valid through library migrations.
 */

import { ReactElement } from 'react';
import { render, RenderOptions, waitFor } from '@testing-library/react';
import userEvent, { type UserEvent } from '@testing-library/user-event';
import { expect } from 'vitest';
import { KeyboardProvider } from '../js/collaborative-editor/keyboard/KeyboardProvider';
import { escape } from 'querystring';

/**
 * Platform-specific key event helpers
 */
export const keys = {
  /**
   * Mac modifier (Cmd/Meta)
   */
  cmd: (key: string) => `{Meta>}${key}{/Meta}`,

  /**
   * Windows/Linux modifier (Ctrl)
   */
  ctrl: (key: string) => `{Control>}${key}{/Control}`,

  /**
   * Common keyboard shortcuts
   */
  save: (variant: 'cmd' | 'ctrl' = 'cmd') => {
    switch (variant) {
      case 'cmd':
        return keys.cmd('s');
      case 'ctrl':
        return keys.ctrl('s');
    }
  },
  saveAndSync: (variant: 'cmd' | 'ctrl' = 'cmd') => {
    switch (variant) {
      case 'cmd':
        return keys.cmd('{Shift>}s{/Shift}');
      case 'ctrl':
        return keys.ctrl('{Shift>}s{/Shift}');
    }
  },
  run: (variant: 'cmd' | 'ctrl' = 'cmd') => {
    switch (variant) {
      case 'cmd':
        return keys.cmd('{Enter}');
      case 'ctrl':
        return keys.ctrl('{Enter}');
    }
  },
  forceRun: (variant: 'cmd' | 'ctrl' = 'cmd') => {
    switch (variant) {
      case 'cmd':
        return `{Meta>}{Shift>}{Enter}{/Shift}{/Meta}`;
      case 'ctrl':
        return `{Control>}{Shift>}{Enter}{/Shift}{/Control}`;
    }
  },
  openIDE: (variant: 'cmd' | 'ctrl' = 'cmd') => {
    switch (variant) {
      case 'cmd':
        return keys.cmd('e');
      case 'ctrl':
        return keys.ctrl('e');
    }
  },
  escape: () => '{Escape}',
};

/**
 * Test keyboard shortcuts on both Mac (Cmd) and Windows/Linux (Ctrl)
 *
 * @example
 * await testPlatformVariants(async (modifierKey) => {
 *   await user.keyboard(`${modifierKey}s`);
 *   await waitFor(() => expect(mockSave).toHaveBeenCalled());
 * });
 */
export async function testPlatformVariants(
  testFn: (modifierKey: string) => Promise<void>
) {
  // Test Mac (Cmd/metaKey)
  await testFn('{Meta>}');

  // Test Windows/Linux (Ctrl/ctrlKey)
  await testFn('{Control>}');
}

/**
 * Create a test wrapper with KeyboardProvider
 *
 * @example
 * render(<Component />, { wrapper: createKeyboardWrapper() });
 */
export function createKeyboardWrapper() {
  return function Wrapper({ children }: { children: ReactElement }) {
    return <KeyboardProvider>{children}</KeyboardProvider>;
  };
}

type Variant = 'cmd' | 'ctrl';

function createKeyboardKeys(user: UserEvent) {
  return {
    save: (variant?: Variant) => {
      return user.keyboard(keys.save(variant));
    },
    saveAndSync: (variant?: Variant) => {
      return user.keyboard(keys.saveAndSync(variant));
    },
    run: (variant?: Variant) => {
      return user.keyboard(keys.run(variant));
    },
    openIDE: (variant?: Variant) => {
      return user.keyboard(keys.openIDE(variant));
    },
    escape: () => user.keyboard(keys.escape()),
  };
}

/**
 * Custom render with KeyboardProvider wrapper and userEvent setup
 *
 * @example
 * const { user } = renderWithKeyboard(<Component />);
 */
export function renderWithKeyboard(
  ui: ReactElement,
  options?: Omit<RenderOptions, 'wrapper'>
) {
  const user = userEvent.setup();
  return {
    user,
    shortcuts: createKeyboardKeys(user),
    ...render(ui, {
      wrapper: createKeyboardWrapper(),
      ...options,
    }),
  };
}

/**
 * Test that a keyboard shortcut does NOT trigger an action
 *
 * @example
 * await expectShortcutNotToFire('{Meta>}s{/Meta}', mockSave, user);
 */
export async function expectShortcutNotToFire(
  keyString: string,
  mockFn: any,
  user: any
) {
  const callCountBefore = mockFn.mock.calls.length;
  await user.keyboard(keyString);

  // Wait a bit to ensure handler doesn't fire
  await new Promise(resolve => setTimeout(resolve, 50));

  expect(mockFn.mock.calls.length).toBe(callCountBefore);
}

/**
 * Focus an element and ensure it's the active element
 */
export function focusElement(element: HTMLElement) {
  element.focus();
  expect(document.activeElement).toBe(element);
}

/**
 * Create mock functions for common keyboard shortcut handlers
 */
export function createKeyboardMocks() {
  return {
    saveWorkflow: vi.fn(),
    openGitHubSyncModal: vi.fn(),
    updateSearchParams: vi.fn(),
    openRunPanel: vi.fn(),
    onClose: vi.fn(),
    handleRun: vi.fn(),
    handleRetry: vi.fn(),
  };
}

/**
 * Common test state for keyboard shortcuts
 */
export function createTestState(overrides: any = {}) {
  return {
    canSave: true,
    canRun: true,
    isRunning: false,
    isRetryable: false,
    isIDEOpen: false,
    isRunPanelOpen: false,
    respondToHotKey: true,
    currentNode: null,
    repoConnection: null,
    workflow: { triggers: [] },
    ...overrides,
  };
}
