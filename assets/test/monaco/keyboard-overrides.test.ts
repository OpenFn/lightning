/**
 * Monaco keyboard override tests
 *
 * Monaco claims a handful of Cmd/Ctrl combos for its own commands. These
 * overrides re-dispatch them on `window` so the application's keyboard system
 * can handle them instead.
 */

import type { editor } from 'monaco-editor';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import type { Monaco } from '../../js/monaco';
import { addKeyboardShortcutOverrides } from '../../js/monaco/keyboard-overrides';

// Arbitrary but distinct values; only their combination matters here.
const KeyMod = { CtrlCmd: 2048, Shift: 1024 } as const;
const KeyCode = { Enter: 3, KeyE: 35, KeyF: 36, KeyK: 41 } as const;

function setupEditor() {
  const commands = new Map<number, () => void>();

  const editorStub = {
    addCommand: (keybinding: number, handler: () => void) => {
      commands.set(keybinding, handler);
    },
  } as unknown as editor.IStandaloneCodeEditor;

  const monacoStub = { KeyMod, KeyCode } as unknown as Monaco;

  addKeyboardShortcutOverrides(editorStub, monacoStub);

  return commands;
}

function setUserAgent(userAgent: string) {
  Object.defineProperty(navigator, 'userAgent', {
    value: userAgent,
    configurable: true,
  });
}

const originalUserAgent = navigator.userAgent;

describe('addKeyboardShortcutOverrides', () => {
  let dispatched: KeyboardEvent[];
  let listener: (event: Event) => void;

  beforeEach(() => {
    dispatched = [];
    listener = event => {
      dispatched.push(event as KeyboardEvent);
    };
    window.addEventListener('keydown', listener);
  });

  afterEach(() => {
    window.removeEventListener('keydown', listener);
    setUserAgent(originalUserAgent);
    vi.restoreAllMocks();
  });

  test('registers an override for Mod+E', () => {
    const commands = setupEditor();

    expect(commands.has(KeyMod.CtrlCmd | KeyCode.KeyE)).toBe(true);
  });

  test('Mod+E dispatches a Cmd+E keydown on Mac', () => {
    setUserAgent('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)');
    const commands = setupEditor();

    commands.get(KeyMod.CtrlCmd | KeyCode.KeyE)?.();

    expect(dispatched).toHaveLength(1);
    expect(dispatched[0]).toMatchObject({
      key: 'e',
      code: 'KeyE',
      metaKey: true,
      ctrlKey: false,
    });
  });

  test('Mod+E dispatches a Ctrl+E keydown off Mac', () => {
    setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64)');
    const commands = setupEditor();

    commands.get(KeyMod.CtrlCmd | KeyCode.KeyE)?.();

    expect(dispatched).toHaveLength(1);
    expect(dispatched[0]).toMatchObject({
      key: 'e',
      code: 'KeyE',
      metaKey: false,
      ctrlKey: true,
    });
  });

  test('leaves Mod+F to Monaco so the find widget still opens', () => {
    const commands = setupEditor();

    expect(commands.has(KeyMod.CtrlCmd | KeyCode.KeyF)).toBe(false);
  });
});
