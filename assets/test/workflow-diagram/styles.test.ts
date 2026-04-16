/**
 * Tests for nodeIconStyles - verifying node border/fill colors
 * for different run step states including the 'running' state.
 */

import { describe, expect, test } from 'vitest';

import { nodeIconStyles, EDGE_COLOR } from '../../js/workflow-diagram/styles';

describe('nodeIconStyles', () => {
  test('returns default colors when no run state', () => {
    const result = nodeIconStyles(false, false, null);
    expect(result.style.stroke).toBe(EDGE_COLOR);
    expect(result.style.fill).toBe('white');
  });

  test('returns green for success', () => {
    const result = nodeIconStyles(false, false, 'success');
    expect(result.style.stroke).toBe('#00a63e');
    expect(result.style.fill).toBe('#dcfce7');
  });

  test('returns red for fail', () => {
    const result = nodeIconStyles(false, false, 'fail');
    expect(result.style.stroke).toBe('#e7000b');
    expect(result.style.fill).toBe('#ffe2e2');
  });

  test('returns orange for crash', () => {
    const result = nodeIconStyles(false, false, 'crash');
    expect(result.style.stroke).toBe('#f54a00');
    expect(result.style.fill).toBe('#ffedd4');
  });

  test('returns blue for running state', () => {
    const result = nodeIconStyles(false, false, 'running');
    expect(result.style.stroke).toBe('#3b82f6');
    expect(result.style.fill).toBe('#dbeafe');
  });

  test('selected state overrides run state border color', () => {
    const running = nodeIconStyles(true, false, 'running');
    expect(running.style.stroke).toBe('#4f46e5'); // EDGE_COLOR_SELECTED

    const success = nodeIconStyles(true, false, 'success');
    expect(success.style.stroke).toBe('#4f46e5');
  });

  test('error state overrides run state border color', () => {
    const result = nodeIconStyles(false, true, 'running');
    expect(result.style.stroke).toBe('#ef4444'); // ERROR_COLOR
    // Fill still reflects run state
    expect(result.style.fill).toBe('#dbeafe');
  });

  test('returns default colors when run state is undefined (via default param)', () => {
    const result = nodeIconStyles(false, false);
    expect(result.style.stroke).toBe(EDGE_COLOR);
    expect(result.style.fill).toBe('white');
  });
});
