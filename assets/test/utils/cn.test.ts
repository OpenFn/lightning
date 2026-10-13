import { describe, expect, test } from 'vitest';

import { cn } from '#/utils/cn';

describe('cn with design token classes', () => {
  test('keeps a text size and a text colour together', () => {
    expect(cn('text-body-sm', 'text-subtle')).toBe('text-body-sm text-subtle');
    expect(cn('border-sm', 'border-muted')).toBe('border-sm border-muted');
  });

  test('lets the last token win over a clashing class', () => {
    expect(cn('p-4', 'p-sm')).toBe('p-sm');
    expect(cn('text-sm', 'text-body-sm')).toBe('text-body-sm');
    expect(cn('rounded-md', 'rounded-pill')).toBe('rounded-pill');
  });
});
