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
    expect(result.style.stroke).toBe('var(--color-green-600)');
    expect(result.style.fill).toBe('var(--color-green-100)');
  });

  test('returns red for fail', () => {
    const result = nodeIconStyles(false, false, 'fail');
    expect(result.style.stroke).toBe('var(--color-red-600)');
    expect(result.style.fill).toBe('var(--color-red-100)');
  });

  test('returns orange for crash', () => {
    const result = nodeIconStyles(false, false, 'crash');
    expect(result.style.stroke).toBe('var(--color-orange-600)');
    expect(result.style.fill).toBe('var(--color-orange-100)');
  });

  test('returns blue for running state', () => {
    const result = nodeIconStyles(false, false, 'running');
    expect(result.style.stroke).toBe('var(--color-blue-500)');
    expect(result.style.fill).toBe('var(--color-blue-100)');
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
    expect(result.style.fill).toBe('var(--color-blue-100)');
  });

  test('returns default colors when run state is undefined (via default param)', () => {
    const result = nodeIconStyles(false, false);
    expect(result.style.stroke).toBe(EDGE_COLOR);
    expect(result.style.fill).toBe('white');
  });
});
