import type { editor } from 'monaco-editor';
import * as monaco from 'monaco-editor';
import {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useRef,
  useState,
} from 'react';
import { MonacoBinding } from 'y-monaco';
import type { Awareness } from 'y-protocols/awareness';
import type * as Y from 'yjs';

import { cn } from '#/utils/cn';
import _logger from '#/utils/logger';

import { type Monaco, MonacoEditor, setTheme } from '../../monaco';
import { addKeyboardShortcutOverrides } from '../../monaco/keyboard-overrides';

import { Cursors } from './Cursors';
import { Tooltip } from './Tooltip';

export interface MonacoHandle {
  showDiff: (originalCode: string, modifiedCode: string) => void;
  clearDiff: () => void;
  getEditor: () => editor.IStandaloneCodeEditor | null;
}

interface CollaborativeMonacoProps {
  ytext: Y.Text;
  awareness: Awareness;
  adaptor?: string;
  disabled?: boolean;
  className?: string;
  options?: editor.IStandaloneEditorConstructionOptions;
  onDiffDismissed?: () => void;
}

export const CollaborativeMonaco = forwardRef<
  MonacoHandle,
  CollaborativeMonacoProps
>(function CollaborativeMonaco(
  {
    ytext,
    awareness,
    adaptor = 'common',
    disabled = false,
    className,
    options = {},
    onDiffDismissed,
  }: CollaborativeMonacoProps,
  ref
) {
  const editorRef = useRef<editor.IStandaloneCodeEditor>();
  const monacoRef = useRef<Monaco>();
  const bindingRef = useRef<MonacoBinding>();
  const [editorReady, setEditorReady] = useState(false);

  // Diff mode state
  const [diffMode, setDiffMode] = useState(false);
  const diffEditorRef = useRef<editor.IStandaloneDiffEditor | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const diffContainerRef = useRef<HTMLDivElement | null>(null);

  const handleOnMount = useCallback(
    (editor: editor.IStandaloneCodeEditor, monaco: Monaco) => {
      editorRef.current = editor;
      monacoRef.current = monaco;
      setEditorReady(true);

      setTheme(monaco);

      const language = getLanguageFromAdaptor(adaptor);
      monaco.editor.setModelLanguage(editor.getModel()!, language);

      addKeyboardShortcutOverrides(editor, monaco);

      // Don't create binding here - let the useEffect handle it
      // This ensures binding is created/updated whenever ytext changes
    },
    [adaptor]
  );

  useEffect(() => {
    if (!editorRef.current || !ytext || !awareness) {
      if (bindingRef.current && !ytext) {
        bindingRef.current.destroy();
        bindingRef.current = undefined;
      }
      return;
    }

    if (bindingRef.current) {
      bindingRef.current.destroy();
      bindingRef.current = undefined;
    }

    const binding = new MonacoBinding(
      ytext,
      editorRef.current.getModel()!,
      new Set([editorRef.current]),
      awareness
    );
    bindingRef.current = binding;

    return () => {
      if (bindingRef.current) {
        bindingRef.current.destroy();
        bindingRef.current = undefined;
      }
    };
  }, [ytext, awareness, editorReady]);

  useEffect(() => {
    return () => {
      if (bindingRef.current) {
        bindingRef.current.destroy();
      }
    };
  }, []);

  useEffect(() => {
    if (editorRef.current) {
      editorRef.current.updateOptions({ readOnly: disabled });
    }
  }, [disabled]);

  useEffect(() => {
    const handleInsertSnippet = (e: Event) => {
      const editor = editorRef.current;
      const monaco = monacoRef.current;
      if (!editor || !monaco) {
        console.error(
          '[CollaborativeMonaco] ❌ Insert snippet: editor or monaco not ready',
          {
            hasEditor: !!editor,
            hasMonaco: !!monaco,
          }
        );
        return;
      }

      // @ts-ignore - custom event property
      const snippetText = e.snippet;
      if (!snippetText) {
        console.error(
          '[CollaborativeMonaco] ❌ Insert snippet: no snippet text in event'
        );
        return;
      }

      const model = editor.getModel();
      if (!model) return;

      const selection = editor.getSelection();
      if (!selection) return;

      const position = selection.getStartPosition();

      const op = {
        range: new monaco.Range(
          position.lineNumber,
          position.column,
          position.lineNumber,
          position.column
        ),
        text: `\n${snippetText}\n`,
        forceMoveMarkers: true,
      };

      editor.executeEdits('insert-snippet', [op]);

      const lines = snippetText.split('\n');
      const newLineNumber = position.lineNumber + lines.length + 1;
      editor.setPosition({ lineNumber: newLineNumber, column: 1 });

      editor.revealLineInCenter(newLineNumber);

      editor.focus();
    };

    document.addEventListener('insert-snippet', handleInsertSnippet);

    return () => {
      document.removeEventListener('insert-snippet', handleInsertSnippet);
    };
  }, []);

  // showDiff function - creates diff editor overlay
  const showDiff = useCallback(
    (originalCode: string, modifiedCode: string) => {
      if (!diffContainerRef.current) {
        return;
      }

      // If already in diff mode, clear the existing diff first
      if (diffMode && diffEditorRef.current) {
        const diffEditor = diffEditorRef.current;
        const model = diffEditor.getModel();
        if (model) {
          model.original?.dispose();
          model.modified?.dispose();
        }
        diffEditor.dispose();
        diffEditorRef.current = null;
      }

      // Hide standard editor container (but don't dispose - Y.Doc still bound)
      if (containerRef.current) {
        containerRef.current.style.setProperty('display', 'none');
      }

      // Show diff container
      if (diffContainerRef.current) {
        diffContainerRef.current.style.setProperty('display', 'block');
      }

      // Create diff editor in dedicated container
      const diffEditor = monaco.editor.createDiffEditor(
        diffContainerRef.current,
        {
          theme: 'vs-dark',
          readOnly: true,
          originalEditable: false,
          automaticLayout: true,
          scrollbar: {
            vertical: 'visible',
            horizontal: 'visible',
          },
          minimap: {
            enabled: false,
          },
        }
      );

      // Create models
      const originalModel = monaco.editor.createModel(
        originalCode,
        'javascript'
      );
      const modifiedModel = monaco.editor.createModel(
        modifiedCode,
        'javascript'
      );

      // Set models
      diffEditor.setModel({
        original: originalModel,
        modified: modifiedModel,
      });

      diffEditorRef.current = diffEditor;
      setDiffMode(true);
    },
    [diffMode]
  );

  // clearDiff function - removes diff editor and shows standard editor
  const clearDiff = useCallback(() => {
    if (!diffMode || !diffEditorRef.current) return;

    // Dispose diff editor and models
    const diffEditor = diffEditorRef.current;
    const model = diffEditor.getModel();

    if (model) {
      model.original?.dispose();
      model.modified?.dispose();
    }

    diffEditor.dispose();
    diffEditorRef.current = null;

    // Hide diff container
    if (diffContainerRef.current) {
      diffContainerRef.current.style.setProperty('display', 'none');
    }

    // Show standard editor container again
    if (containerRef.current) {
      containerRef.current.style.setProperty('display', 'block');
    }

    // Focus standard editor
    if (editorRef.current) {
      editorRef.current.focus();
    }

    setDiffMode(false);

    // Notify parent component that diff was dismissed
    onDiffDismissed?.();
  }, [diffMode, onDiffDismissed]);

  // Expose functions via ref
  useImperativeHandle(
    ref,
    () => ({
      showDiff,
      clearDiff,
      getEditor: () => editorRef.current || null,
    }),
    [showDiff, clearDiff]
  );

  const editorOptions: editor.IStandaloneEditorConstructionOptions = {
    fontSize: 14,
    minimap: { enabled: false },
    scrollBeyondLastLine: false,
    wordWrap: 'on',
    lineNumbers: 'on',
    folding: true,
    renderWhitespace: 'selection',
    tabSize: 2,
    insertSpaces: true,
    automaticLayout: true,
    readOnly: disabled,
    fixedOverflowWidgets: true,
    ...options,
  };

  return (
    <div className={cn('relative', className || 'h-full w-full')}>
      {/* Standard editor container */}
      <div ref={containerRef} className="h-full w-full">
        <Cursors />
        <MonacoEditor
          onMount={handleOnMount}
          options={editorOptions}
          theme="default"
          language={getLanguageFromAdaptor(adaptor)}
        />
      </div>
      {/* Diff editor container - hidden by default */}
      <div
        ref={diffContainerRef}
        className="h-full w-full absolute inset-0"
        style={{ display: 'none' }}
      >
        {/* Dismiss button - only visible when diff is showing */}
        {diffMode && (
          <Tooltip content="Close diff preview" side="left">
            <button
              type="button"
              onClick={clearDiff}
              className={cn(
                'absolute top-4 right-4 z-[60]',
                'flex items-center justify-center',
                'h-8 w-8 rounded-md',
                'bg-gray-800/90 hover:bg-gray-700',
                'text-gray-300 hover:text-white',
                'border border-gray-600',
                'transition-colors duration-150',
                'focus:outline-none focus:ring-2 focus:ring-primary-500'
              )}
              aria-label="Close diff preview"
            >
              <span className="hero-x-mark h-5 w-5" />
            </button>
          </Tooltip>
        )}
      </div>
    </div>
  );
});

function getLanguageFromAdaptor(adaptor: string): string {
  switch (adaptor) {
    case 'javascript':
    case 'js':
      return 'javascript';
    case 'typescript':
    case 'ts':
      return 'typescript';
    case 'json':
      return 'json';
    case 'html':
      return 'html';
    case 'css':
      return 'css';
    default:
      return 'javascript';
  }
}
