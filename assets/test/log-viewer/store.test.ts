/**
 * Log Store Tests
 *
 * Tests for the log viewer store, focusing on:
 * - Log deduplication by ID
 * - Log sorting by timestamp
 * - Log level filtering
 * - Step-based highlighting
 */

import { beforeEach, describe, expect, test } from 'vitest';
import { createLogStore, type LogLine } from '../../js/log-viewer/store';

describe('LogStore', () => {
  let store: ReturnType<typeof createLogStore>;

  beforeEach(() => {
    store = createLogStore();
  });

  describe('addLogLines', () => {
    test('adds new logs to the store', () => {
      const logs: LogLine[] = [
        {
          id: 'log-1',
          message: 'Test message',
          source: 'RTE',
          level: 'info',
          step_id: 'step-1',
          timestamp: new Date('2025-01-01T00:00:00Z'),
        },
      ];

      store.getState().addLogLines(logs);

      expect(store.getState().logLines).toHaveLength(1);
      expect(store.getState().logLines[0].id).toBe('log-1');
    });

    test('deduplicates logs by ID', () => {
      const log1: LogLine = {
        id: 'log-1',
        message: 'First version',
        source: 'RTE',
        level: 'info',
        step_id: 'step-1',
        timestamp: new Date('2025-01-01T00:00:00Z'),
      };

      const log2: LogLine = {
        id: 'log-1', // Same ID!
        message: 'Second version',
        source: 'RTE',
        level: 'info',
        step_id: 'step-1',
        timestamp: new Date('2025-01-01T00:00:01Z'),
      };

      // Add first log
      store.getState().addLogLines([log1]);
      expect(store.getState().logLines).toHaveLength(1);
      expect(store.getState().logLines[0].message).toBe('First version');

      // Try to add duplicate
      store.getState().addLogLines([log2]);

      // Should still only have one log, and it should be the original
      expect(store.getState().logLines).toHaveLength(1);
      expect(store.getState().logLines[0].message).toBe('First version');
    });

    test('sorts logs by timestamp', () => {
      const logs: LogLine[] = [
        {
          id: 'log-3',
          message: 'Third',
          source: 'RTE',
          level: 'info',
          step_id: 'step-1',
          timestamp: new Date('2025-01-01T00:00:02Z'),
        },
        {
          id: 'log-1',
          message: 'First',
          source: 'RTE',
          level: 'info',
          step_id: 'step-1',
          timestamp: new Date('2025-01-01T00:00:00Z'),
        },
        {
          id: 'log-2',
          message: 'Second',
          source: 'RTE',
          level: 'info',
          step_id: 'step-1',
          timestamp: new Date('2025-01-01T00:00:01Z'),
        },
      ];

      store.getState().addLogLines(logs);

      const sortedLogs = store.getState().logLines;
      expect(sortedLogs[0].message).toBe('First');
      expect(sortedLogs[1].message).toBe('Second');
      expect(sortedLogs[2].message).toBe('Third');
    });

    test('handles string timestamps from backend', () => {
      const logsWithStringTimestamp = [
        {
          id: 'log-1',
          message: 'Test',
          source: 'RTE',
          level: 'info',
          step_id: 'step-1',
          timestamp: '2025-01-01T00:00:00Z' as any,
        },
      ];

      store.getState().addLogLines(logsWithStringTimestamp);

      const addedLog = store.getState().logLines[0];
      expect(addedLog.timestamp).toBeInstanceOf(Date);
    });

    test('formats logs into string representation', () => {
      const logs: LogLine[] = [
        {
          id: 'log-1',
          message: 'Test message',
          source: 'RTE',
          level: 'info',
          step_id: 'step-1',
          timestamp: new Date('2025-01-01T00:00:00Z'),
        },
      ];

      store.getState().addLogLines(logs);

      const formatted = store.getState().formattedLogLines;
      expect(formatted).toContain('RTE');
      expect(formatted).toContain('Test message');
    });
  });

  describe('log level filtering', () => {
    const createLogWithLevel = (
      id: string,
      level: string,
      message: string
    ): LogLine => ({
      id,
      message,
      source: 'RTE',
      level,
      step_id: 'step-1',
      timestamp: new Date('2025-01-01T00:00:00Z'),
    });

    test('filters logs based on desired log level', () => {
      const logs: LogLine[] = [
        createLogWithLevel('log-1', 'debug', 'Debug message'),
        createLogWithLevel('log-2', 'info', 'Info message'),
        createLogWithLevel('log-3', 'warn', 'Warning message'),
        createLogWithLevel('log-4', 'error', 'Error message'),
      ];

      store.getState().addLogLines(logs);

      // Set to show only warnings and above
      store.getState().setDesiredLogLevel('warn');

      const formatted = store.getState().formattedLogLines;

      // Should include warn and error
      expect(formatted).toContain('Warning message');
      expect(formatted).toContain('Error message');

      // Should not include debug and info
      expect(formatted).not.toContain('Debug message');
      expect(formatted).not.toContain('Info message');
    });

    test('defaults to info level', () => {
      expect(store.getState().desiredLogLevel).toBe('info');
    });

    test('updates formatted logs when log level changes', () => {
      const logs: LogLine[] = [
        createLogWithLevel('log-1', 'debug', 'Debug message'),
        createLogWithLevel('log-2', 'info', 'Info message'),
      ];

      store.getState().addLogLines(logs);

      // Initially at info level - should not see debug
      let formatted = store.getState().formattedLogLines;
      expect(formatted).not.toContain('Debug message');
      expect(formatted).toContain('Info message');

      // Change to debug level - should see both
      store.getState().setDesiredLogLevel('debug');
      formatted = store.getState().formattedLogLines;
      expect(formatted).toContain('Debug message');
      expect(formatted).toContain('Info message');
    });
  });

  describe('step selection and highlighting', () => {
    test('updates stepId', () => {
      store.getState().setStepId('step-1');
      expect(store.getState().stepId).toBe('step-1');
    });

    test('highlights logs for selected step', () => {
      const logs: LogLine[] = [
        {
          id: 'log-1',
          message: 'Step 1 log',
          source: 'RTE',
          level: 'info',
          step_id: 'step-1',
          timestamp: new Date('2025-01-01T00:00:00Z'),
        },
        {
          id: 'log-2',
          message: 'Step 2 log',
          source: 'RTE',
          level: 'info',
          step_id: 'step-2',
          timestamp: new Date('2025-01-01T00:00:01Z'),
        },
      ];

      store.getState().addLogLines(logs);
      store.getState().setStepId('step-1');

      // Should have highlighted ranges for step-1
      const ranges = store.getState().highlightedRanges;
      expect(ranges.length).toBeGreaterThan(0);
    });

    test('clears highlights when no step selected', () => {
      const logs: LogLine[] = [
        {
          id: 'log-1',
          message: 'Test',
          source: 'RTE',
          level: 'info',
          step_id: 'step-1',
          timestamp: new Date('2025-01-01T00:00:00Z'),
        },
      ];

      store.getState().addLogLines(logs);
      store.getState().setStepId('step-1');

      // Should have highlights
      expect(store.getState().highlightedRanges.length).toBeGreaterThan(0);

      // Clear step selection
      store.getState().setStepId(undefined);

      // Should have no highlights
      expect(store.getState().highlightedRanges.length).toBe(0);
    });
  });

  describe('JSON prettification', () => {
    test('prettifies JSON in log messages', () => {
      const logs: LogLine[] = [
        {
          id: 'log-1',
          message: '{"key":"value","nested":{"foo":"bar"}}',
          source: 'RTE',
          level: 'info',
          step_id: 'step-1',
          timestamp: new Date('2025-01-01T00:00:00Z'),
        },
      ];

      store.getState().addLogLines(logs);

      const formatted = store.getState().formattedLogLines;

      // Should be formatted with indentation
      expect(formatted).toContain('{\n');
      expect(formatted).toContain('  ');
    });

    test('leaves non-JSON messages unchanged', () => {
      const logs: LogLine[] = [
        {
          id: 'log-1',
          message: 'Plain text message',
          source: 'RTE',
          level: 'info',
          step_id: 'step-1',
          timestamp: new Date('2025-01-01T00:00:00Z'),
        },
      ];

      store.getState().addLogLines(logs);

      const formatted = store.getState().formattedLogLines;
      expect(formatted).toContain('Plain text message');
    });
  });
});
