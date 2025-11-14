/**
 * Test utilities for keyboard shortcut testing
 *
 * These utilities provide library-agnostic helpers for testing keyboard
 * shortcuts. They test user-facing behavior rather than implementation
 * details, ensuring tests remain valid through library migrations.
 */

import { ReactElement } from 'react';
import {
  render,
  RenderOptions,
  fireEvent,
  waitFor,
} from '@testing-library/react';
import { KeyboardProvider } from '../js/collaborative-editor/keyboard/KeyboardProvider';

/**
 * Platform-specific key event helpers
 */
export const keys = {
  /**
   * Mac modifier (Cmd/Meta)
   */
  cmd: (key: string, options: Partial<KeyboardEventInit> = {}) => ({
    key,
    metaKey: true,
    ...options,
  }),

  /**
   * Windows/Linux modifier (Ctrl)
   */
  ctrl: (key: string, options: Partial<KeyboardEventInit> = {}) => ({
    key,
    ctrlKey: true,
    ...options,
  }),

  /**
   * Platform-agnostic modifier (returns both Mac and Windows variants)
   * Use with testPlatformVariants() to test both
   */
  mod: (key: string, options: Partial<KeyboardEventInit> = {}) => [
    { key, metaKey: true, ...options },
    { key, ctrlKey: true, ...options },
  ],

  /**
   * Common keyboard shortcuts
   */
  save: () => keys.mod('s'),
  saveAndSync: () => keys.mod('s', { shiftKey: true }),
  run: () => keys.mod('Enter'),
  forceRun: () => keys.mod('Enter', { shiftKey: true }),
  openIDE: () => keys.mod('e'),
  escape: () => ({ key: 'Escape' }),
};

/**
 * Test keyboard shortcuts on both Mac (Cmd) and Windows/Linux (Ctrl)
 *
 * @example
 * await testPlatformVariants(async (modifierKey) => {
 *   fireEvent.keyDown(document, { key: 's', ...modifierKey });
 *   await waitFor(() => expect(mockSave).toHaveBeenCalled());
 * });
 */
export async function testPlatformVariants(
  testFn: (
    modifierKey: { metaKey: boolean } | { ctrlKey: boolean }
  ) => Promise<void>
) {
  // Test Mac (Cmd/metaKey)
  await testFn({ metaKey: true });

  // Test Windows/Linux (Ctrl/ctrlKey)
  await testFn({ ctrlKey: true });
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

/**
 * Custom render with KeyboardProvider wrapper
 *
 * @example
 * renderWithKeyboard(<Component />);
 */
export function renderWithKeyboard(
  ui: ReactElement,
  options?: Omit<RenderOptions, 'wrapper'>
) {
  return render(ui, {
    wrapper: createKeyboardWrapper(),
    ...options,
  });
}

/**
 * Simulate keyboard event on target element or document
 *
 * @example
 * // Fire on document (global shortcut)
 * pressKey('s', { metaKey: true });
 *
 * // Fire on specific element
 * const input = screen.getByRole('textbox');
 * pressKey('s', { metaKey: true }, input);
 */
export function pressKey(
  key: string,
  modifiers: Partial<KeyboardEventInit> = {},
  target: Element | Document | Window = document
) {
  // For react-hotkeys-hook, we need to dispatch a real KeyboardEvent
  // fireEvent.keyDown doesn't trigger the hook handlers properly
  const event = new KeyboardEvent('keydown', {
    key,
    bubbles: true,
    cancelable: true,
    ...modifiers,
  });

  // If target is document, dispatch on window as well for react-hotkeys-hook
  if (target === document || target === window) {
    window.dispatchEvent(event);
  } else {
    target.dispatchEvent(event);
  }
}

/**
 * Simulate keyboard shortcut and wait for expected result
 *
 * @example
 * await pressKeyAndWait('s', { metaKey: true }, () => {
 *   expect(mockSave).toHaveBeenCalled();
 * });
 */
export async function pressKeyAndWait(
  key: string,
  modifiers: Partial<KeyboardEventInit>,
  assertion: () => void,
  target: Element | Document = document
) {
  pressKey(key, modifiers, target);
  await waitFor(assertion);
}

/**
 * Test that a keyboard shortcut does NOT trigger an action
 *
 * @example
 * await expectShortcutNotToFire('s', { metaKey: true }, mockSave);
 */
export async function expectShortcutNotToFire(
  key: string,
  modifiers: Partial<KeyboardEventInit>,
  mockFn: any,
  target: Element | Document = document
) {
  const callCountBefore = mockFn.mock.calls.length;
  pressKey(key, modifiers, target);

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
 * Test keyboard shortcut behavior in different contexts
 */
export const testContexts = {
  /**
   * Test shortcut works in an input field
   */
  async inInput(
    key: string,
    modifiers: Partial<KeyboardEventInit>,
    assertion: () => void
  ) {
    const input = document.createElement('input');
    input.setAttribute('data-testid', 'test-input');
    document.body.appendChild(input);
    focusElement(input);

    await pressKeyAndWait(key, modifiers, assertion, input);

    document.body.removeChild(input);
  },

  /**
   * Test shortcut works in a textarea
   */
  async inTextarea(
    key: string,
    modifiers: Partial<KeyboardEventInit>,
    assertion: () => void
  ) {
    const textarea = document.createElement('textarea');
    textarea.setAttribute('data-testid', 'test-textarea');
    document.body.appendChild(textarea);
    focusElement(textarea);

    await pressKeyAndWait(key, modifiers, assertion, textarea);

    document.body.removeChild(textarea);
  },

  /**
   * Test shortcut works in a select
   */
  async inSelect(
    key: string,
    modifiers: Partial<KeyboardEventInit>,
    assertion: () => void
  ) {
    const select = document.createElement('select');
    select.setAttribute('data-testid', 'test-select');
    const option = document.createElement('option');
    option.value = 'test';
    option.textContent = 'Test Option';
    select.appendChild(option);
    document.body.appendChild(select);
    focusElement(select);

    await pressKeyAndWait(key, modifiers, assertion, select);

    document.body.removeChild(select);
  },

  /**
   * Test shortcut works in contentEditable
   */
  async inContentEditable(
    key: string,
    modifiers: Partial<KeyboardEventInit>,
    assertion: () => void
  ) {
    const div = document.createElement('div');
    div.setAttribute('contenteditable', 'true');
    div.setAttribute('data-testid', 'test-contenteditable');
    document.body.appendChild(div);
    focusElement(div);

    await pressKeyAndWait(key, modifiers, assertion, div);

    document.body.removeChild(div);
  },
};

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
