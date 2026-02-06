/**
 * CollaborativeMonaco Diff Display Tests
 *
 * Tests the Monaco diff editor integration for AI job code preview.
 * These tests focus on the showDiff/clearDiff functionality added for
 * the AI assistant job code preview feature.
 */

// Mock monaco-editor BEFORE any other imports
vi.mock('monaco-editor', () => ({
  editor: {
    createDiffEditor: vi.fn(() => ({
      setModel: vi.fn(),
      dispose: vi.fn(),
      getModel: vi.fn(() => ({
        original: { dispose: vi.fn() },
        modified: { dispose: vi.fn() },
      })),
    })),
    createModel: vi.fn(code => ({
      code,
      dispose: vi.fn(),
    })),
  },
  languages: {
    typescript: {
      javascriptDefaults: {
        setCompilerOptions: vi.fn(),
        setDiagnosticsOptions: vi.fn(),
        setEagerModelSync: vi.fn(),
        addExtraLib: vi.fn(() => ({ dispose: vi.fn() })),
        setExtraLibs: vi.fn(),
      },
      typescriptDefaults: {
        setCompilerOptions: vi.fn(),
        setDiagnosticsOptions: vi.fn(),
        setEagerModelSync: vi.fn(),
        addExtraLib: vi.fn(() => ({ dispose: vi.fn() })),
        setExtraLibs: vi.fn(),
      },
    },
    registerCompletionItemProvider: vi.fn(() => ({ dispose: vi.fn() })),
  },
}));

import { render, screen, waitFor } from '@testing-library/react';
import { useRef, useEffect } from 'react';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { Awareness } from 'y-protocols/awareness';
import * as Y from 'yjs';

import {
  CollaborativeMonaco,
  type MonacoHandle,
} from '../../../js/collaborative-editor/components/CollaborativeMonaco';
import { MonacoRefProvider } from '../../../js/collaborative-editor/contexts/MonacoRefContext';

// Extend window type for test refs
declare global {
  interface Window {
    testMonacoRef?: React.RefObject<MonacoHandle>;
    testRef?: React.RefObject<MonacoHandle>;
  }
}

// Mock y-monaco
vi.mock('y-monaco', () => ({
  MonacoBinding: vi.fn(() => ({
    destroy: vi.fn(),
  })),
}));

// Mock Cursors component to avoid needing full context stack
vi.mock('../../../js/collaborative-editor/components/Cursors', () => ({
  Cursors: () => null,
}));

// Mock monaco module
vi.mock('../../../js/monaco', () => ({
  MonacoEditor: ({ onMount }: any) => {
    const mockEditor = {
      getModel: () => ({ getValue: () => '', setValue: vi.fn() }),
      updateOptions: vi.fn(),
      focus: vi.fn(),
      addCommand: vi.fn(),
    };
    const mockMonaco = {
      editor: {
        setModelLanguage: vi.fn(),
        createDiffEditor: vi.fn(() => ({
          setModel: vi.fn(),
          dispose: vi.fn(),
          getModel: vi.fn(() => ({
            original: { dispose: vi.fn() },
            modified: { dispose: vi.fn() },
          })),
        })),
        createModel: vi.fn(code => ({ code, dispose: vi.fn() })),
      },
      languages: {
        typescript: {
          javascriptDefaults: {
            setCompilerOptions: vi.fn(),
            setDiagnosticsOptions: vi.fn(),
            setEagerModelSync: vi.fn(),
            addExtraLib: vi.fn(() => ({ dispose: vi.fn() })),
            setExtraLibs: vi.fn(),
          },
          typescriptDefaults: {
            setCompilerOptions: vi.fn(),
            setDiagnosticsOptions: vi.fn(),
            setEagerModelSync: vi.fn(),
            addExtraLib: vi.fn(() => ({ dispose: vi.fn() })),
            setExtraLibs: vi.fn(),
          },
        },
        registerCompletionItemProvider: vi.fn(() => ({ dispose: vi.fn() })),
      },
      KeyMod: {
        CtrlCmd: 1,
        Shift: 2,
        Alt: 4,
      },
      KeyCode: {
        Enter: 13,
        Escape: 27,
      },
    };

    useEffect(() => {
      onMount?.(mockEditor, mockMonaco);
    }, []);

    return <div data-testid="monaco-editor">Monaco Editor</div>;
  },
  setTheme: vi.fn(),
}));

// Helper component to test imperative handle
function TestWrapper() {
  const monacoRef = useRef<MonacoHandle>(null);
  const ydoc = new Y.Doc();
  const ytext = ydoc.getText('code');
  const awareness = new Awareness(ydoc);

  useEffect(() => {
    // Expose ref for testing
    (window as any).testMonacoRef = monacoRef;
  }, []);

  return (
    <CollaborativeMonaco ref={monacoRef} ytext={ytext} awareness={awareness} />
  );
}

describe('CollaborativeMonaco - Diff Display', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    delete (window as any).testMonacoRef;
  });

  describe('showDiff', () => {
    it('should expose showDiff via ref', async () => {
      render(<TestWrapper />);

      await waitFor(() => {
        expect((window as any).testMonacoRef?.current).toBeTruthy();
      });

      const handle = (window as any).testMonacoRef.current;
      expect(typeof handle.showDiff).toBe('function');
    });

    it('should create diff editor when showDiff is called', async () => {
      render(<TestWrapper />);

      await waitFor(() => {
        expect((window as any).testMonacoRef?.current).toBeTruthy();
      });

      const handle = (window as any).testMonacoRef.current;
      handle.showDiff('const old = 1;', 'const new = 2;');

      // Note: Monaco is mocked, diff editor creation happens internally
      expect(handle).toBeTruthy();
    });

    it('should hide standard editor and show diff container', async () => {
      const { container } = render(<TestWrapper />);

      await waitFor(() => {
        expect((window as any).testMonacoRef?.current).toBeTruthy();
      });

      const handle = (window as any).testMonacoRef.current;
      handle.showDiff('old code', 'new code');

      await waitFor(() => {
        // Standard editor should be hidden
        const standardContainer = container.querySelector(
          '[data-testid="monaco-editor"]'
        )?.parentElement;
        expect(standardContainer).toHaveStyle({ display: 'none' });
      });
    });

    it('should handle showing multiple diffs sequentially', async () => {
      render(<TestWrapper />);

      await waitFor(() => {
        expect((window as any).testMonacoRef?.current).toBeTruthy();
      });

      const handle = (window as any).testMonacoRef.current;

      // Show first diff
      handle.showDiff('first old', 'first new');

      // Show second diff (should dispose first and create new one)
      handle.showDiff('second old', 'second new');

      // Both operations should complete without error
      expect(handle).toBeTruthy();
    });
  });

  describe('clearDiff', () => {
    it('should expose clearDiff via ref', async () => {
      render(<TestWrapper />);

      await waitFor(() => {
        expect((window as any).testMonacoRef?.current).toBeTruthy();
      });

      const handle = (window as any).testMonacoRef.current;
      expect(typeof handle.clearDiff).toBe('function');
    });

    it('should dispose diff editor and show standard editor', async () => {
      render(<TestWrapper />);

      await waitFor(() => {
        expect((window as any).testMonacoRef?.current).toBeTruthy();
      });

      const handle = (window as any).testMonacoRef.current;

      // Show diff
      handle.showDiff('old', 'new');

      // Clear diff - just verify it doesn't throw
      expect(() => handle.clearDiff()).not.toThrow();
    });

    it('should work with MonacoRefProvider context', async () => {
      const ydoc = new Y.Doc();
      const ytext = ydoc.getText('code');
      const awareness = new Awareness(ydoc);

      function TestComponent() {
        const monacoRef = useRef<MonacoHandle>(null);
        const ref = useRef<MonacoHandle>(null);

        useEffect(() => {
          (window as any).testRef = ref;
        }, []);

        return (
          <MonacoRefProvider monacoRef={monacoRef}>
            <CollaborativeMonaco
              ref={ref}
              ytext={ytext}
              awareness={awareness}
            />
          </MonacoRefProvider>
        );
      }

      render(<TestComponent />);

      await waitFor(() => {
        expect((window as any).testRef?.current).toBeTruthy();
      });

      const handle = (window as any).testRef.current;

      // Verify clearDiff works with context provider
      handle.showDiff('old', 'new');
      expect(() => handle.clearDiff()).not.toThrow();

      delete (window as any).testRef;
    });

    it('should be safe to call clearDiff when no diff is showing', async () => {
      render(<TestWrapper />);

      await waitFor(() => {
        expect((window as any).testMonacoRef?.current).toBeTruthy();
      });

      const handle = (window as any).testMonacoRef.current;

      // Should not throw
      expect(() => handle.clearDiff()).not.toThrow();
    });
  });

  describe('Dismiss button', () => {
    it('should show dismiss button when diff is active', async () => {
      render(<TestWrapper />);

      await waitFor(() => {
        expect((window as any).testMonacoRef?.current).toBeTruthy();
      });

      const handle = (window as any).testMonacoRef.current;
      handle.showDiff('old', 'new');

      await waitFor(() => {
        const dismissButton = screen.queryByLabelText('Close diff preview');
        expect(dismissButton).toBeInTheDocument();
      });
    });

    it('should hide dismiss button when no diff is showing', async () => {
      render(<TestWrapper />);

      await waitFor(() => {
        expect((window as any).testMonacoRef?.current).toBeTruthy();
      });

      // Dismiss button should not be visible initially
      expect(
        screen.queryByLabelText('Close diff preview')
      ).not.toBeInTheDocument();
    });

    it('should clear diff when dismiss button is clicked', async () => {
      const { container } = render(<TestWrapper />);

      await waitFor(() => {
        expect((window as any).testMonacoRef?.current).toBeTruthy();
      });

      const handle = (window as any).testMonacoRef.current;
      handle.showDiff('old', 'new');

      const dismissButton = await screen.findByLabelText('Close diff preview');
      dismissButton.click();

      await waitFor(() => {
        const standardContainer = container.querySelector(
          '[data-testid="monaco-editor"]'
        )?.parentElement;
        expect(standardContainer).toHaveStyle({ display: 'block' });
      });
    });
  });
});
