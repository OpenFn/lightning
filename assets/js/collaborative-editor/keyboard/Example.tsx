/**
 * Example component demonstrating all keyboard shortcut features
 *
 * This is for documentation purposes only. Not used in production.
 */

import { useState } from 'react';

import { KeyboardProvider, useKeyboardShortcut } from './index';

// Define priorities for this example (applications should define their own)
const PRIORITY = {
  MODAL: 100,
  IDE: 50,
  PANEL: 10,
  DEFAULT: 0,
};

function ModalExample() {
  const [isOpen, setIsOpen] = useState(false);

  useKeyboardShortcut(
    'Escape',
    () => {
      console.log('Modal: Closing modal');
      setIsOpen(false);
    },
    PRIORITY.MODAL,
    {
      enabled: isOpen, // Only active when modal is open
    }
  );

  return (
    <div>
      <button onClick={() => setIsOpen(true)}>Open Modal</button>
      {isOpen && (
        <div style={{ border: '2px solid blue', padding: '20px' }}>
          <h2>Modal (Priority: 100)</h2>
          <p>Press ESC to close</p>
        </div>
      )}
    </div>
  );
}

function IDEExample() {
  const [monacoHasFocus, setMonacoHasFocus] = useState(false);

  useKeyboardShortcut(
    'Escape',
    () => {
      if (monacoHasFocus) {
        console.log('IDE: Blurring Monaco, passing to next handler');
        setMonacoHasFocus(false);
        return false; // Pass to next handler
      }
      console.log('IDE: Closing IDE');
      return undefined;
    },
    PRIORITY.IDE
  );

  return (
    <div style={{ border: '2px solid green', padding: '20px' }}>
      <h2>IDE (Priority: 50)</h2>
      <p>Press ESC to close (or blur Monaco if focused)</p>
      <input
        placeholder="Simulate Monaco focus"
        onFocus={() => setMonacoHasFocus(true)}
        onBlur={() => setMonacoHasFocus(false)}
      />
      {monacoHasFocus && (
        <p>Monaco focused - ESC will blur and pass to next handler</p>
      )}
    </div>
  );
}

function PanelExample() {
  const [isOpen, setIsOpen] = useState(true);

  useKeyboardShortcut(
    'Escape',
    () => {
      console.log('Panel: Closing panel');
      setIsOpen(false);
    },
    PRIORITY.PANEL
  );

  if (!isOpen)
    return <button onClick={() => setIsOpen(true)}>Open Panel</button>;

  return (
    <div style={{ border: '2px solid orange', padding: '20px' }}>
      <h2>Panel (Priority: 10)</h2>
      <p>Press ESC to close</p>
    </div>
  );
}

function MultiComboExample() {
  const [log, setLog] = useState<string[]>([]);

  useKeyboardShortcut(
    'Cmd+Enter, Ctrl+Enter',
    () => {
      const msg = 'Cmd/Ctrl+Enter pressed';
      console.log(msg);
      setLog(prev => [...prev, msg]);
    },
    PRIORITY.DEFAULT
  );

  return (
    <div style={{ border: '2px solid purple', padding: '20px' }}>
      <h2>Multi-Combo Example</h2>
      <p>Press Cmd+Enter or Ctrl+Enter</p>
      <ul>
        {log.map((entry, i) => (
          <li key={i}>{entry}</li>
        ))}
      </ul>
    </div>
  );
}

export function KeyboardExample() {
  return (
    <KeyboardProvider>
      <div
        style={{
          padding: '20px',
          display: 'flex',
          flexDirection: 'column',
          gap: '20px',
        }}
      >
        <h1>Keyboard Shortcuts Example</h1>
        <p>Open browser console to see logs</p>

        <ModalExample />
        <IDEExample />
        <PanelExample />
        <MultiComboExample />

        <div
          style={{ marginTop: '20px', padding: '10px', background: '#f0f0f0' }}
        >
          <h3>Priority Order (ESC key):</h3>
          <ol>
            <li>Modal (100) - Only when modal is open</li>
            <li>IDE (50) - Returns false if Monaco focused</li>
            <li>Panel (10) - Runs if IDE returns false or isn't registered</li>
          </ol>
        </div>
      </div>
    </KeyboardProvider>
  );
}
