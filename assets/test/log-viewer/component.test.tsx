/**
 * LogViewer Component Tests
 *
 * Tests the LogViewer component focusing on Monaco Editor
 * initialization race conditions where logs arrive via WebSocket
 * before Monaco is fully ready.
 *
 * This addresses the race condition fixed in PR #4110 where logs
 * would disappear on browser refresh in the collaborative editor IDE.
 */

import { screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { createLogStore, type LogLine } from '../../js/log-viewer/store';

// Mock @monaco-editor/react to prevent loading issues
vi.mock('@monaco-editor/react', () => ({
  default: ({ value }: { value: string }) => (
    <div data-testid="monaco-editor" data-value={value}>
      {value || 'Loading...'}
    </div>
  ),
}));

// Mock the monaco module that LogViewer imports
vi.mock('../../js/monaco', () => ({
  MonacoEditor: ({
    value,
    loading,
  }: {
    value: string;
    loading?: React.ReactNode;
  }) => (
    <div data-testid="monaco-editor" data-value={value || ''}>
      {loading || value || 'Editor'}
    </div>
  ),
}));

// Import mount after mocks are set up
const { mount } = await import('../../js/log-viewer/component');

describe('LogViewer Component - Monaco Initialization Race Conditions', () => {
  let store: ReturnType<typeof createLogStore>;
  let container: HTMLElement;

  const sampleLogs: LogLine[] = [
    {
      id: 'log-1',
      message: 'Test log message 1',
      source: 'RTE',
      level: 'info',
      step_id: 'step-1',
      timestamp: new Date('2025-01-01T00:00:00Z'),
    },
    {
      id: 'log-2',
      message: 'Test log message 2',
      source: 'RTE',
      level: 'info',
      step_id: 'step-1',
      timestamp: new Date('2025-01-01T00:00:01Z'),
    },
  ];

  beforeEach(() => {
    vi.clearAllMocks();
    store = createLogStore();
    container = document.createElement('div');
    document.body.appendChild(container);
  });

  afterEach(() => {
    document.body.removeChild(container);
  });

  test('renders Monaco editor component', async () => {
    mount(container, store);

    await waitFor(() => {
      const editor = container.querySelector('[data-testid="monaco-editor"]');
      expect(editor).not.toBeNull();
    });
  });

  test('handles logs that arrive before component mount (race condition)', async () => {
    // Step 1: Add logs to store BEFORE mounting component
    store.getState().addLogLines(sampleLogs);
    const expectedContent = store.getState().formattedLogLines;

    // Step 2: Mount component
    mount(container, store);

    // Step 3: Wait for Monaco to receive the value prop
    await waitFor(() => {
      const editor = screen.getByTestId('monaco-editor');
      const dataValue = editor.getAttribute('data-value');
      expect(dataValue).toBe(expectedContent);
    });

    // Verify both log messages are in the content
    expect(expectedContent).toContain('Test log message 1');
    expect(expectedContent).toContain('Test log message 2');
  });

  test('handles logs that arrive immediately after mount', async () => {
    // Another race condition: logs arrive right after component mounts

    // Step 1: Mount component first
    mount(container, store);

    // Step 2: Logs arrive immediately (within milliseconds)
    store.getState().addLogLines(sampleLogs);
    const expectedContent = store.getState().formattedLogLines;

    // Step 3: useMonacoSync should handle this and apply the value
    await waitFor(() => {
      const editor = screen.getByTestId('monaco-editor');
      const dataValue = editor.getAttribute('data-value');
      expect(dataValue).toBe(expectedContent);
    });
  });

  test('handles multiple rapid log updates before editor ready', async () => {
    // Simulate multiple log batches arriving rapidly

    mount(container, store);

    // Multiple rapid updates
    const logs1: LogLine[] = [
      {
        id: 'log-1',
        message: 'First batch',
        source: 'RTE',
        level: 'info',
        step_id: 'step-1',
        timestamp: new Date('2025-01-01T00:00:00Z'),
      },
    ];

    const logs2: LogLine[] = [
      {
        id: 'log-2',
        message: 'Second batch',
        source: 'RTE',
        level: 'info',
        step_id: 'step-1',
        timestamp: new Date('2025-01-01T00:00:01Z'),
      },
    ];

    const logs3: LogLine[] = [
      {
        id: 'log-3',
        message: 'Third batch',
        source: 'RTE',
        level: 'info',
        step_id: 'step-1',
        timestamp: new Date('2025-01-01T00:00:02Z'),
      },
    ];

    store.getState().addLogLines(logs1);
    store.getState().addLogLines(logs2);
    store.getState().addLogLines(logs3);

    const finalContent = store.getState().formattedLogLines;

    await waitFor(() => {
      const editor = screen.getByTestId('monaco-editor');
      const dataValue = editor.getAttribute('data-value');
      expect(dataValue).toBe(finalContent);
    });

    // All three batches should be in the final content
    expect(finalContent).toContain('First batch');
    expect(finalContent).toContain('Second batch');
    expect(finalContent).toContain('Third batch');
  });

  test('updates when new logs arrive after initial render', async () => {
    // Test that subsequent log updates continue to work

    mount(container, store);

    // First batch of logs
    store.getState().addLogLines([sampleLogs[0]]);

    await waitFor(() => {
      const editor = screen.getByTestId('monaco-editor');
      const dataValue = editor.getAttribute('data-value') || '';
      expect(dataValue).toContain('Test log message 1');
    });

    // Second batch arrives
    store.getState().addLogLines([sampleLogs[1]]);

    await waitFor(() => {
      const editor = screen.getByTestId('monaco-editor');
      const dataValue = editor.getAttribute('data-value') || '';
      expect(dataValue).toContain('Test log message 1');
      expect(dataValue).toContain('Test log message 2');
    });
  });

  test('handles log level filtering', async () => {
    // Test that log level filtering works with the sync

    const debugLog: LogLine = {
      id: 'log-debug',
      message: 'Debug message',
      source: 'RTE',
      level: 'debug',
      step_id: 'step-1',
      timestamp: new Date('2025-01-01T00:00:00Z'),
    };

    const infoLog: LogLine = {
      id: 'log-info',
      message: 'Info message',
      source: 'RTE',
      level: 'info',
      step_id: 'step-1',
      timestamp: new Date('2025-01-01T00:00:01Z'),
    };

    // Set to info level (default) - debug should be filtered out
    store.getState().setDesiredLogLevel('info');
    store.getState().addLogLines([debugLog, infoLog]);

    mount(container, store);

    await waitFor(() => {
      const editor = screen.getByTestId('monaco-editor');
      const dataValue = editor.getAttribute('data-value') || '';
      expect(dataValue).toContain('Info message');
      expect(dataValue).not.toContain('Debug message');
    });

    // Change to debug level - both should appear
    store.getState().setDesiredLogLevel('debug');

    await waitFor(() => {
      const editor = screen.getByTestId('monaco-editor');
      const dataValue = editor.getAttribute('data-value') || '';
      expect(dataValue).toContain('Info message');
      expect(dataValue).toContain('Debug message');
    });
  });
});
