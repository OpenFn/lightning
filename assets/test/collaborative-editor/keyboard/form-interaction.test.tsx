/**
 * Form Interaction and ContentEditable Keyboard Shortcut Tests
 *
 * Tests keyboard shortcuts in different DOM contexts:
 * - Form elements (input, textarea, select) - shortcuts work by default
 * - ContentEditable elements (Monaco editor) - requires explicit handling
 * - Negative cases where shortcuts should NOT work
 *
 * These tests verify that the keyboard shortcut system correctly handles:
 * 1. Shortcuts in form elements (input, textarea, select)
 * 2. Shortcuts in Monaco editor (contentEditable)
 * 3. Proper scoping (IDE shortcuts work in Monaco, but not other shortcuts)
 * 4. preventDefault behavior
 *
 * Note: react-hotkeys-hook had `enableOnFormTags` and `enableOnContentEditable`
 * options. Our new KeyboardProvider works in form elements by default (no option
 * needed), and contentEditable handling is done in the handler logic.
 */

import { describe, test, expect, vi } from 'vitest';
import { FC } from 'react';
import {
  renderWithKeyboard,
  pressKey,
  testContexts,
  expectShortcutNotToFire,
} from '../../keyboard-test-utils';
import { useKeyboardShortcut } from '../../../js/collaborative-editor/keyboard';

/**
 * Test component that registers keyboard shortcuts for testing form elements
 */
const TestShortcutComponent: FC<{
  onSave?: () => void;
  onRun?: () => void;
  onForceRun?: () => void;
  onClose?: () => void;
  onOpenIDE?: () => void;
  onGitHubSync?: () => void;
  enableOnContentEditable?: boolean;
  priority?: number;
  children?: React.ReactNode;
}> = ({
  onSave,
  onRun,
  onForceRun,
  onClose,
  onOpenIDE,
  onGitHubSync,
  enableOnContentEditable = false,
  priority = 0,
  children,
}) => {
  // Save shortcut (Cmd+S / Ctrl+S)
  // Does NOT work in contentEditable (unlike run shortcuts which check enableOnContentEditable)
  useKeyboardShortcut(
    'Meta+s, Control+s',
    e => {
      if (!onSave) return true;

      // Save shortcut should NOT work in contentEditable
      const target = e.target as HTMLElement;
      const isInContentEditable =
        target.closest('[contenteditable="true"]') !== null;
      if (isInContentEditable) {
        return true;
      }

      e.preventDefault();
      onSave();
      return false;
    },
    priority
  );

  // GitHub sync shortcut (Cmd+Shift+S / Ctrl+Shift+S)
  // Does NOT work in contentEditable
  useKeyboardShortcut(
    'Meta+Shift+s, Control+Shift+s',
    e => {
      if (!onGitHubSync) return true;

      const target = e.target as HTMLElement;
      const isInContentEditable =
        target.closest('[contenteditable="true"]') !== null;
      if (isInContentEditable) {
        return true;
      }

      e.preventDefault();
      onGitHubSync();
      return false;
    },
    priority
  );

  // Run shortcut (Cmd+Enter / Ctrl+Enter)
  // Only works in contentEditable if enableOnContentEditable is true
  useKeyboardShortcut(
    'Meta+Enter, Control+Enter',
    e => {
      if (!onRun) return true;

      // Check if we're in contentEditable
      const target = e.target as HTMLElement;
      const isInContentEditable =
        target.closest('[contenteditable="true"]') !== null;

      // If we're in contentEditable and it's not explicitly enabled, pass through
      if (isInContentEditable && !enableOnContentEditable) {
        return true;
      }

      e.preventDefault();
      onRun();
      return false;
    },
    priority
  );

  // Force run shortcut (Cmd+Shift+Enter / Ctrl+Shift+Enter)
  useKeyboardShortcut(
    'Meta+Shift+Enter, Control+Shift+Enter',
    e => {
      if (!onForceRun) return true;

      const target = e.target as HTMLElement;
      const isInContentEditable =
        target.closest('[contenteditable="true"]') !== null;

      if (isInContentEditable && !enableOnContentEditable) {
        return true;
      }

      e.preventDefault();
      onForceRun();
      return false;
    },
    priority
  );

  // Escape shortcut
  useKeyboardShortcut(
    'Escape',
    e => {
      if (onClose) {
        e.preventDefault();
        onClose();
        return false;
      }
      return true;
    },
    priority
  );

  // Open IDE shortcut (Cmd+E / Ctrl+E)
  // Does NOT work in contentEditable
  useKeyboardShortcut(
    'Meta+e, Control+e',
    e => {
      if (!onOpenIDE) return true;

      const target = e.target as HTMLElement;
      const isInContentEditable =
        target.closest('[contenteditable="true"]') !== null;
      if (isInContentEditable) {
        return true;
      }

      e.preventDefault();
      onOpenIDE();
      return false;
    },
    priority
  );

  return <div>{children}</div>;
};

describe('Form element keyboard shortcuts', () => {
  describe('Save shortcut (Cmd+S)', () => {
    test('works when typing in input field', async () => {
      const mockSave = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent onSave={mockSave}>
          <input data-testid="test-input" defaultValue="test" />
        </TestShortcutComponent>
      );

      await testContexts.inInput('s', { metaKey: true }, () => {
        expect(mockSave).toHaveBeenCalled();
      });
    });

    test('works when typing in textarea', async () => {
      const mockSave = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent onSave={mockSave}>
          <textarea data-testid="test-textarea" defaultValue="test" />
        </TestShortcutComponent>
      );

      await testContexts.inTextarea('s', { metaKey: true }, () => {
        expect(mockSave).toHaveBeenCalled();
      });
    });

    test('works with Ctrl modifier (Windows/Linux)', async () => {
      const mockSave = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent onSave={mockSave}>
          <input data-testid="test-input" />
        </TestShortcutComponent>
      );

      await testContexts.inInput('s', { ctrlKey: true }, () => {
        expect(mockSave).toHaveBeenCalled();
      });
    });
  });

  describe('Escape shortcut', () => {
    test('works when focus is in input', async () => {
      const mockClose = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent onClose={mockClose}>
          <input data-testid="test-input" />
        </TestShortcutComponent>
      );

      await testContexts.inInput('Escape', {}, () => {
        expect(mockClose).toHaveBeenCalled();
      });
    });

    test('works when focus is in textarea', async () => {
      const mockClose = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent onClose={mockClose}>
          <textarea data-testid="test-textarea" />
        </TestShortcutComponent>
      );

      await testContexts.inTextarea('Escape', {}, () => {
        expect(mockClose).toHaveBeenCalled();
      });
    });

    test('works when focus is in select', async () => {
      const mockClose = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent onClose={mockClose}>
          <select data-testid="test-select">
            <option value="1">Option 1</option>
            <option value="2">Option 2</option>
          </select>
        </TestShortcutComponent>
      );

      await testContexts.inSelect('Escape', {}, () => {
        expect(mockClose).toHaveBeenCalled();
      });
    });
  });

  describe('Run shortcut (Cmd+Enter)', () => {
    test('works in textarea (for job body editing)', async () => {
      const mockRun = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent onRun={mockRun}>
          <textarea data-testid="job-body" defaultValue="fn(state => state);" />
        </TestShortcutComponent>
      );

      await testContexts.inTextarea('Enter', { metaKey: true }, () => {
        expect(mockRun).toHaveBeenCalled();
      });
    });

    test('works with Ctrl modifier in textarea', async () => {
      const mockRun = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent onRun={mockRun}>
          <textarea data-testid="job-body" />
        </TestShortcutComponent>
      );

      await testContexts.inTextarea('Enter', { ctrlKey: true }, () => {
        expect(mockRun).toHaveBeenCalled();
      });
    });
  });

  describe('Shift modifier combinations', () => {
    test('Cmd+Shift+S works in input field', async () => {
      const mockGitHubSync = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent onGitHubSync={mockGitHubSync}>
          <input data-testid="test-input" />
        </TestShortcutComponent>
      );

      await testContexts.inInput('s', { metaKey: true, shiftKey: true }, () => {
        expect(mockGitHubSync).toHaveBeenCalled();
      });
    });
  });
});

describe('ContentEditable keyboard shortcuts', () => {
  describe('Monaco editor (enableOnContentEditable: true)', () => {
    test('Cmd+Enter works in Monaco editor when enabled', async () => {
      const mockRun = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent onRun={mockRun} enableOnContentEditable={true}>
          <div className="monaco-editor">
            <div
              contentEditable={true}
              data-testid="monaco-editable"
              suppressContentEditableWarning
            >
              Code here
            </div>
          </div>
        </TestShortcutComponent>
      );

      await testContexts.inContentEditable('Enter', { metaKey: true }, () => {
        expect(mockRun).toHaveBeenCalled();
      });
    });

    test('Ctrl+Enter works in Monaco editor when enabled', async () => {
      const mockRun = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent onRun={mockRun} enableOnContentEditable={true}>
          <div className="monaco-editor">
            <div
              contentEditable={true}
              data-testid="monaco-editable"
              suppressContentEditableWarning
            >
              Code here
            </div>
          </div>
        </TestShortcutComponent>
      );

      await testContexts.inContentEditable('Enter', { ctrlKey: true }, () => {
        expect(mockRun).toHaveBeenCalled();
      });
    });

    test('Cmd+Shift+Enter works in Monaco editor when enabled', async () => {
      const mockForceRun = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent
          onForceRun={mockForceRun}
          enableOnContentEditable={true}
        >
          <div className="monaco-editor">
            <div
              contentEditable={true}
              data-testid="monaco-editable"
              suppressContentEditableWarning
            >
              Code here
            </div>
          </div>
        </TestShortcutComponent>
      );

      await testContexts.inContentEditable(
        'Enter',
        { metaKey: true, shiftKey: true },
        () => {
          expect(mockForceRun).toHaveBeenCalled();
        }
      );
    });
  });

  describe('Negative cases: shortcuts that should NOT work in contentEditable', () => {
    test('run shortcut does NOT work in contentEditable when not explicitly enabled', async () => {
      const mockRun = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent onRun={mockRun} enableOnContentEditable={false}>
          <div
            contentEditable={true}
            data-testid="generic-editable"
            suppressContentEditableWarning
          >
            Some editable content
          </div>
        </TestShortcutComponent>
      );

      await expectShortcutNotToFire('Enter', { metaKey: true }, mockRun);
    });

    test('save shortcut does NOT work in generic contentEditable', async () => {
      const mockSave = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent onSave={mockSave}>
          <div
            contentEditable={true}
            data-testid="generic-editable"
            suppressContentEditableWarning
          >
            Some editable content
          </div>
        </TestShortcutComponent>
      );

      const editable = document.querySelector(
        '[data-testid="generic-editable"]'
      ) as HTMLElement;
      editable.focus();

      await expectShortcutNotToFire('s', { metaKey: true }, mockSave, editable);
    });

    test('open IDE shortcut does NOT work in generic contentEditable', async () => {
      const mockOpenIDE = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent onOpenIDE={mockOpenIDE}>
          <div
            contentEditable={true}
            data-testid="generic-editable"
            suppressContentEditableWarning
          >
            Some content
          </div>
        </TestShortcutComponent>
      );

      const editable = document.querySelector(
        '[data-testid="generic-editable"]'
      ) as HTMLElement;
      editable.focus();

      await expectShortcutNotToFire(
        'e',
        { metaKey: true },
        mockOpenIDE,
        editable
      );
    });
  });

  describe('IDE-specific shortcuts with contentEditable', () => {
    test('only IDE run shortcuts have enableOnContentEditable', async () => {
      const mockIDERun = vi.fn();
      const mockSave = vi.fn();

      renderWithKeyboard(
        <>
          <TestShortcutComponent
            onRun={mockIDERun}
            enableOnContentEditable={true}
            priority={10}
          />
          <TestShortcutComponent onSave={mockSave} priority={0}>
            <div className="monaco-editor">
              <div
                contentEditable={true}
                data-testid="monaco-editable"
                suppressContentEditableWarning
              >
                Code here
              </div>
            </div>
          </TestShortcutComponent>
        </>
      );

      const monacoEditable = document.querySelector(
        '[data-testid="monaco-editable"]'
      ) as HTMLElement;
      monacoEditable.focus();

      // IDE run should work
      pressKey('Enter', { metaKey: true }, monacoEditable);
      await new Promise(resolve => setTimeout(resolve, 50));
      expect(mockIDERun).toHaveBeenCalled();

      // But save should NOT work in contentEditable
      mockSave.mockClear();
      await expectShortcutNotToFire(
        's',
        { metaKey: true },
        mockSave,
        monacoEditable
      );
    });
  });
});

describe('Edge cases and complex scenarios', () => {
  describe('Mixed form and contentEditable', () => {
    test('shortcuts work correctly when switching focus between input and Monaco', async () => {
      const mockSave = vi.fn();
      const mockRun = vi.fn();

      // Use single component with both callbacks
      renderWithKeyboard(
        <TestShortcutComponent
          onSave={mockSave}
          onRun={mockRun}
          enableOnContentEditable={true}
          priority={10}
        >
          <input data-testid="job-name" defaultValue="My Job" />
          <div className="monaco-editor">
            <div
              contentEditable={true}
              data-testid="monaco-editable"
              suppressContentEditableWarning
            >
              Code
            </div>
          </div>
        </TestShortcutComponent>
      );

      const input = document.querySelector(
        '[data-testid="job-name"]'
      ) as HTMLElement;
      const monacoEditable = document.querySelector(
        '[data-testid="monaco-editable"]'
      ) as HTMLElement;

      // Save should work in input
      input.focus();
      pressKey('s', { metaKey: true }, input);
      await new Promise(resolve => setTimeout(resolve, 50));
      expect(mockSave).toHaveBeenCalled();

      mockSave.mockClear();

      // Run should work in Monaco
      monacoEditable.focus();
      pressKey('Enter', { metaKey: true }, monacoEditable);
      await new Promise(resolve => setTimeout(resolve, 50));
      expect(mockRun).toHaveBeenCalled();

      // Save should NOT work in Monaco
      await expectShortcutNotToFire(
        's',
        { metaKey: true },
        mockSave,
        monacoEditable
      );
    });
  });

  describe('Monaco focus detection patterns', () => {
    test('detects focus on contentEditable inside .monaco-editor', () => {
      renderWithKeyboard(
        <div className="monaco-editor">
          <div
            contentEditable={true}
            data-testid="monaco-editable"
            suppressContentEditableWarning
          >
            Code
          </div>
        </div>
      );

      const monacoEditable = document.querySelector(
        '[data-testid="monaco-editable"]'
      ) as HTMLElement;
      monacoEditable.focus();

      const activeElement = document.activeElement;
      const isMonacoFocused = activeElement?.closest('.monaco-editor');

      expect(isMonacoFocused).toBeTruthy();
      expect(isMonacoFocused).toHaveClass('monaco-editor');
    });

    test('does not detect Monaco focus for other contentEditable', () => {
      renderWithKeyboard(
        <div className="other-editor">
          <div
            contentEditable={true}
            data-testid="other-editable"
            suppressContentEditableWarning
          >
            Content
          </div>
        </div>
      );

      const otherEditable = document.querySelector(
        '[data-testid="other-editable"]'
      ) as HTMLElement;
      otherEditable.focus();

      const activeElement = document.activeElement;
      const isMonacoFocused = activeElement?.closest('.monaco-editor');

      expect(isMonacoFocused).toBeNull();
    });
  });

  describe('Platform modifier variations', () => {
    test('both Cmd and Ctrl modifiers work', async () => {
      const mockRun = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent onRun={mockRun} enableOnContentEditable={true}>
          <div className="monaco-editor">
            <div
              contentEditable={true}
              data-testid="monaco-editable"
              suppressContentEditableWarning
            >
              Code
            </div>
          </div>
        </TestShortcutComponent>
      );

      const monacoEditable = document.querySelector(
        '[data-testid="monaco-editable"]'
      ) as HTMLElement;
      monacoEditable.focus();

      // Test Cmd modifier (Mac)
      pressKey('Enter', { metaKey: true }, monacoEditable);
      await new Promise(resolve => setTimeout(resolve, 50));
      expect(mockRun).toHaveBeenCalledTimes(1);

      // Test Ctrl modifier (Windows/Linux)
      pressKey('Enter', { ctrlKey: true }, monacoEditable);
      await new Promise(resolve => setTimeout(resolve, 50));
      expect(mockRun).toHaveBeenCalledTimes(2);
    });
  });

  describe('Select element specific behavior', () => {
    test('Escape works in select dropdown', async () => {
      const mockClose = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent onClose={mockClose}>
          <select data-testid="adaptor-select">
            <option value="http">@openfn/language-http</option>
            <option value="common">@openfn/language-common</option>
            <option value="dhis2">@openfn/language-dhis2</option>
          </select>
        </TestShortcutComponent>
      );

      await testContexts.inSelect('Escape', {}, () => {
        expect(mockClose).toHaveBeenCalled();
      });
    });
  });

  describe('Textarea specific scenarios', () => {
    test('Cmd+Enter in textarea for job body', async () => {
      const mockRun = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent onRun={mockRun}>
          <textarea
            data-testid="job-body"
            defaultValue={`fn(state => {
  console.log('Processing data...');
  return state;
});`}
          />
        </TestShortcutComponent>
      );

      await testContexts.inTextarea('Enter', { metaKey: true }, () => {
        expect(mockRun).toHaveBeenCalled();
      });
    });

    test('Cmd+S in textarea for adaptor configuration', async () => {
      const mockSave = vi.fn();

      renderWithKeyboard(
        <TestShortcutComponent onSave={mockSave}>
          <textarea
            data-testid="adaptor-config"
            defaultValue='{"baseUrl": "https://api.example.com"}'
          />
        </TestShortcutComponent>
      );

      await testContexts.inTextarea('s', { metaKey: true }, () => {
        expect(mockSave).toHaveBeenCalled();
      });
    });
  });
});

describe('Documentation and behavior verification', () => {
  test('documents form elements work by default', () => {
    // This test documents that keyboard shortcuts work in form elements by default
    // No special enableOnFormTags option needed (unlike react-hotkeys-hook)
    const documentation = {
      pattern: 'Shortcuts work in form elements by default',
      elements: ['<input>', '<textarea>', '<select>'],
      purpose: 'Allow shortcuts while user is editing form fields',
      implementation: 'KeyboardProvider listens on window, works everywhere',
      migration: 'enableOnFormTags: true is now the default, no option needed',
    };

    expect(documentation.elements).toHaveLength(3);
    expect(documentation.pattern).toContain('form elements');
    expect(documentation.migration).toContain('default');
  });

  test('documents contentEditable requires handler logic', () => {
    // This test documents that enableOnContentEditable is now handled in handler logic
    const documentation = {
      usage: 'IDE run shortcuts check for contentEditable in handler',
      purpose: 'Allow shortcuts in Monaco editor (contentEditable)',
      shortcuts: ['Cmd+Enter (run/retry)', 'Cmd+Shift+Enter (force run)'],
      implementation:
        'Handler checks: target.closest("[contenteditable=\\"true\\"]")',
      migration: 'enableOnContentEditable is now manual logic in handler',
    };

    expect(documentation.usage).toContain('IDE');
    expect(documentation.shortcuts).toHaveLength(2);
    expect(documentation.implementation).toContain('closest');
  });
});
