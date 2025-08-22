import type { editor } from "monaco-editor";
import { useCallback, useEffect, useRef } from "react";
import { MonacoBinding } from "y-monaco";
import type { Awareness } from "y-protocols/awareness";
import type * as Y from "yjs";

import { type Monaco, MonacoEditor, setTheme } from "../../monaco";

import { Cursors } from "./Cursors";

interface CollaborativeMonacoProps {
  ytext: Y.Text;
  awareness: Awareness;
  adaptor?: string;
  disabled?: boolean;
  className?: string;
  options?: editor.IStandaloneEditorConstructionOptions;
}

export function CollaborativeMonaco({
  ytext,
  awareness,
  adaptor = "common",
  disabled = false,
  className,
  options = {},
}: CollaborativeMonacoProps) {
  const editorRef = useRef<editor.IStandaloneCodeEditor>();
  const monacoRef = useRef<Monaco>();
  const bindingRef = useRef<MonacoBinding>();

  const handleOnMount = useCallback(
    (editor: editor.IStandaloneCodeEditor, monaco: Monaco) => {
      console.log(
        "🚀 Monaco editor mounted, ytext available:",
        !!ytext,
        "awareness available:",
        !!awareness
      );
      editorRef.current = editor;
      monacoRef.current = monaco;

      // Set theme
      setTheme(monaco);

      // Set language based on adaptor
      const language = getLanguageFromAdaptor(adaptor);
      monaco.editor.setModelLanguage(editor.getModel()!, language);

      // Create initial binding if ytext and awareness are available
      if (ytext && awareness) {
        console.log("🔄 Creating initial Monaco binding on mount");
        const binding = new MonacoBinding(
          ytext,
          editor.getModel()!,
          new Set([editor]),
          awareness
        );
        bindingRef.current = binding;
        console.log("✅ Initial Monaco binding created successfully");
      }
    },
    [adaptor, ytext, awareness]
  );

  // Effect to handle Y.Text binding changes after mount
  useEffect(() => {
    console.log(
      "🔄 Monaco binding effect running - editor ready:",
      !!editorRef.current,
      "ytext:",
      !!ytext,
      "awareness:",
      !!awareness,
      "existing binding:",
      !!bindingRef.current
    );

    if (!editorRef.current || !ytext || !awareness) {
      console.log("❌ Monaco binding effect - missing requirements");
      // If editor is ready but ytext is not, clear any existing binding
      if (bindingRef.current && !ytext) {
        bindingRef.current.destroy();
        bindingRef.current = undefined;
      }
      return;
    }

    console.log(
      "🔄 Creating Monaco binding for Y.Text in effect:",
      ytext,
      ytext.toString()
    );

    // Destroy existing binding if it exists (for job switching)
    if (bindingRef.current) {
      console.log("🗑️ Destroying existing Monaco binding for job switch");
      bindingRef.current.destroy();
      bindingRef.current = undefined;
    }

    // Create new binding for the current Y.Text
    const binding = new MonacoBinding(
      ytext,
      editorRef.current.getModel()!,
      new Set([editorRef.current]),
      awareness
    );
    bindingRef.current = binding;

    console.log("✅ Monaco binding created successfully in effect");

    // Clean up binding when ytext or awareness changes
    return () => {
      console.log("🧹 Cleaning up Monaco binding from effect");
      if (bindingRef.current) {
        bindingRef.current.destroy();
        bindingRef.current = undefined;
      }
    };
  }, [ytext, awareness]);

  useEffect(() => {
    // Clean up binding on unmount
    return () => {
      if (bindingRef.current) {
        bindingRef.current.destroy();
      }
    };
  }, []);

  useEffect(() => {
    // Update editor readonly state when disabled changes
    if (editorRef.current) {
      editorRef.current.updateOptions({ readOnly: disabled });
    }
  }, [disabled]);

  const editorOptions: editor.IStandaloneEditorConstructionOptions = {
    fontSize: 14,
    minimap: { enabled: false },
    scrollBeyondLastLine: false,
    wordWrap: "on",
    lineNumbers: "on",
    folding: true,
    renderWhitespace: "selection",
    tabSize: 2,
    insertSpaces: true,
    automaticLayout: true,
    readOnly: disabled,
    ...options,
  };

  return (
    <div className={className || "h-full w-full"}>
      <Cursors />
      <MonacoEditor
        onMount={handleOnMount}
        options={editorOptions}
        theme="default"
        language={getLanguageFromAdaptor(adaptor)}
        // Don't set value prop - Y.Text will control the content
      />
    </div>
  );
}

function getLanguageFromAdaptor(adaptor: string): string {
  // Map adaptor types to Monaco languages
  switch (adaptor) {
    case "javascript":
    case "js":
      return "javascript";
    case "typescript":
    case "ts":
      return "typescript";
    case "json":
      return "json";
    case "html":
      return "html";
    case "css":
      return "css";
    default:
      return "javascript"; // Default to JavaScript
  }
}
