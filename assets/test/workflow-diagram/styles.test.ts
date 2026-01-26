import { describe, expect, test } from 'vitest';

import { sortOrderForSvg } from '../../js/workflow-diagram/styles';

describe.concurrent('sortOrderForSvg', () => {
  test('sorts disabled edges before enabled edges', () => {
    const edges = [
      { data: { enabled: true }, selected: false },
      { data: { enabled: false }, selected: false },
    ];

    const sorted = [...edges].sort(sortOrderForSvg);

    expect(sorted[0].data.enabled).toBe(false);
    expect(sorted[1].data.enabled).toBe(true);
  });

  test('maintains stable order for edges with same enabled status', () => {
    const edges = [
      { id: 'edge1', data: { enabled: true }, selected: false },
      { id: 'edge2', data: { enabled: true }, selected: false },
      { id: 'edge3', data: { enabled: true }, selected: false },
    ];

    const sorted = [...edges].sort(sortOrderForSvg);

    // Order should remain unchanged when all have same enabled status
    expect(sorted[0].id).toBe('edge1');
    expect(sorted[1].id).toBe('edge2');
    expect(sorted[2].id).toBe('edge3');
  });

  test('preserves stable order when selection state changes', () => {
    // This test ensures that selecting edges doesn't cause layout shifts
    const edges = [
      { id: 'edge1', data: { enabled: true }, selected: false },
      { id: 'edge2', data: { enabled: true }, selected: false },
      { id: 'edge3', data: { enabled: true }, selected: false },
    ];

    // Sort once with no selection
    const sortedBefore = [...edges].sort(sortOrderForSvg);

    // Simulate selecting middle edge
    const edgesWithSelection = [
      { id: 'edge1', data: { enabled: true }, selected: false },
      { id: 'edge2', data: { enabled: true }, selected: true },
      { id: 'edge3', data: { enabled: true }, selected: false },
    ];

    const sortedAfter = [...edgesWithSelection].sort(sortOrderForSvg);

    // Order should NOT change when selection changes
    expect(sortedBefore[0].id).toBe(sortedAfter[0].id);
    expect(sortedBefore[1].id).toBe(sortedAfter[1].id);
    expect(sortedBefore[2].id).toBe(sortedAfter[2].id);
  });

  test('handles mix of enabled and disabled edges correctly', () => {
    const edges = [
      { id: 'disabled1', data: { enabled: false }, selected: false },
      { id: 'enabled1', data: { enabled: true }, selected: false },
      { id: 'disabled2', data: { enabled: false }, selected: false },
      { id: 'enabled2', data: { enabled: true }, selected: false },
    ];

    const sorted = [...edges].sort(sortOrderForSvg);

    // All disabled edges should come before enabled edges
    expect(sorted[0].id).toBe('disabled1');
    expect(sorted[1].id).toBe('disabled2');
    expect(sorted[2].id).toBe('enabled1');
    expect(sorted[3].id).toBe('enabled2');
  });

  test('maintains stable order within disabled edge group', () => {
    const edges = [
      { id: 'disabled1', data: { enabled: false }, selected: false },
      { id: 'disabled2', data: { enabled: false }, selected: true },
      { id: 'disabled3', data: { enabled: false }, selected: false },
    ];

    const sorted = [...edges].sort(sortOrderForSvg);

    // Order within disabled group should remain stable regardless of selection
    expect(sorted[0].id).toBe('disabled1');
    expect(sorted[1].id).toBe('disabled2');
    expect(sorted[2].id).toBe('disabled3');
  });
});
