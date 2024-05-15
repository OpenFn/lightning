import React from 'react';
import { createRoot } from 'react-dom/client';
import Monaco from '@monaco-editor/react';

export function mount(el: HTMLElement, content: string) {
  const componentRoot = createRoot(el);

  render(content);

  function render(content: string) {
    console.log('rendering', content);
    componentRoot.render(
      // <Monaco
      //   defaultLanguage="json"
      //   theme="default"
      //   defaultPath="dataclip.json"
      //   value={content}
      //   options={{ readOnly: true }}
      // />
      <div>{content}</div>
    );
  }

  function unmount() {
    return componentRoot.unmount();
  }

  return { unmount, render };
}
