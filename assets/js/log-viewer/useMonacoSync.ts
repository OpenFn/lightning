import { editor as e } from 'monaco-editor';
import { useEffect, useRef, useState } from 'react';

import { type Monaco } from '../monaco';

/**
 * Custom hook to handle Monaco Editor value synchronization.
 *
 * Addresses the race condition where logs arrive before Monaco is fully initialized.
 * Based on guidance from @monaco-editor/react maintainer:
 * https://github.com/suren-atoyan/monaco-react/issues/1
 *
 * The maintainer recommends keeping an "isEditorReady" flag and storing updates
 * that arrive before mount to apply them once the editor is ready.
 *
 * @param editor - Monaco editor instance (from onMount callback)
 * @param monaco - Monaco API instance (from beforeMount callback)
 * @param value - The value to sync to the editor
 */
export function useMonacoSync(
  editor: e.IStandaloneCodeEditor | undefined,
  monaco: Monaco | undefined,
  value: string
) {
  const [isEditorReady, setIsEditorReady] = useState(false);
  const pendingValueRef = useRef<string | null>(null);

  // Track editor ready state
  useEffect(() => {
    if (editor && monaco) {
      setIsEditorReady(true);
    } else {
      setIsEditorReady(false);
    }
  }, [editor, monaco]);

  // Store pending updates that arrive before editor is ready
  useEffect(() => {
    if (!isEditorReady) {
      // Store the latest value to apply once editor is ready
      pendingValueRef.current = value;
    }
  }, [value, isEditorReady]);

  // Apply pending value once editor becomes ready
  useEffect(() => {
    if (isEditorReady && editor && pendingValueRef.current !== null) {
      const currentValue = editor.getValue();
      if (currentValue !== pendingValueRef.current) {
        editor.setValue(pendingValueRef.current);
      }
      pendingValueRef.current = null;
    }
  }, [isEditorReady, editor]);

  // Sync value changes after editor is ready
  useEffect(() => {
    if (isEditorReady && editor && monaco) {
      const currentValue = editor.getValue();
      if (currentValue !== value) {
        editor.setValue(value);
      }
    }
  }, [value, isEditorReady, editor, monaco]);

  return { isEditorReady };
}
