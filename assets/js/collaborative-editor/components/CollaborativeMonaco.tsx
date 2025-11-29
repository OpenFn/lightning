import type { editor } from 'monaco-editor';
import { useCallback, useEffect, useRef } from 'react';
import { MonacoBinding } from 'y-monaco';
import type { Awareness } from 'y-protocols/awareness';
import type * as Y from 'yjs';

import _logger from '#/utils/logger';

import { type Monaco, MonacoEditor, setTheme } from '../../monaco';
import { addKeyboardShortcutOverrides } from '../../monaco/keyboard-overrides';

import { Cursors } from './Cursors';

interface CollaborativeMonacoProps {
  ytext: Y.Text;
  awareness: Awareness;
  adaptor?: string;
  disabled?: boolean;
  className?: string;
  options?: editor.IStandaloneEditorConstructionOptions;
}

const logger = _logger.ns('CollaborativeMonaco').seal();

export function CollaborativeMonaco({
  ytext,
  awareness,
  adaptor = 'common',
  disabled = false,
  className,
  options = {},
}: CollaborativeMonacoProps) {
  const editorRef = useRef<editor.IStandaloneCodeEditor>();
  const monacoRef = useRef<Monaco>();
  const bindingRef = useRef<MonacoBinding>();

  const handleOnMount = useCallback(
    (editor: editor.IStandaloneCodeEditor, monaco: Monaco) => {
      editorRef.current = editor;
      monacoRef.current = monaco;

      setTheme(monaco);

      const language = getLanguageFromAdaptor(adaptor);
      monaco.editor.setModelLanguage(editor.getModel()!, language);

      addKeyboardShortcutOverrides(editor, monaco);

      if (ytext && awareness) {
        const binding = new MonacoBinding(
          ytext,
          editor.getModel()!,
          new Set([editor]),
          awareness
        );
        bindingRef.current = binding;
      }
    },
    [adaptor, ytext, awareness]
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
  }, [ytext, awareness]);

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
    <div className={className || 'h-full w-full'}>
      <Cursors />
      <MonacoEditor
        onMount={handleOnMount}
        options={editorOptions}
        theme="default"
        language={getLanguageFromAdaptor(adaptor)}
      />
    </div>
  );
}

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
