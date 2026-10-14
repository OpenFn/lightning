import { readFileSync } from 'node:fs';

import { describe, expect, test } from 'vitest';

import { build, OUTPUT, readExports } from '../design-tokens/build';
import { cn } from '../js/utils/cn';

describe('design tokens', () => {
  test('committed css/design-tokens.css matches the exports (run `npm run design-tokens`)', () => {
    const { light, statics } = readExports();
    expect(readFileSync(OUTPUT, 'utf8')).toBe(build(light, statics).css);
  });

  test('cn keeps token classes that do different jobs', () => {
    expect(cn('text-ds-type-body-md', 'text-ds-subtle')).toBe(
      'text-ds-type-body-md text-ds-subtle'
    );
    expect(cn('border-ds-width-md', 'border-ds-default')).toBe(
      'border-ds-width-md border-ds-default'
    );
    expect(cn('border-b-ds-width-lg', 'border-b-ds-action-primary')).toBe(
      'border-b-ds-width-lg border-b-ds-action-primary'
    );
    expect(cn('ring-ds-width-md', 'ring-ds-action-primary')).toBe(
      'ring-ds-width-md ring-ds-action-primary'
    );
    expect(cn('outline-ds-width-md', 'outline-ds-default')).toBe(
      'outline-ds-width-md outline-ds-default'
    );
    expect(cn('divide-y-ds-width-md', 'divide-ds-default')).toBe(
      'divide-y-ds-width-md divide-ds-default'
    );
    expect(cn('font-ds-mono', 'font-ds-weight-medium')).toBe(
      'font-ds-mono font-ds-weight-medium'
    );
    expect(cn('bg-ds-default', 'rounded-ds-md', 'p-ds-sm', 'gap-ds-xs')).toBe(
      'bg-ds-default rounded-ds-md p-ds-sm gap-ds-xs'
    );
  });

  test('cn lets a later class replace one that does the same job', () => {
    expect(cn('p-4', 'p-ds-sm')).toBe('p-ds-sm');
    expect(cn('px-2', 'px-ds-xs')).toBe('px-ds-xs');
    expect(cn('gap-2', 'gap-ds-sm')).toBe('gap-ds-sm');
    expect(cn('w-4', 'w-ds-lg')).toBe('w-ds-lg');
    expect(cn('size-4', 'size-ds-lg')).toBe('size-ds-lg');
    expect(cn('rounded-md', 'rounded-ds-pill')).toBe('rounded-ds-pill');
    expect(cn('text-sm', 'text-ds-type-label')).toBe('text-ds-type-label');
    expect(cn('text-gray-500', 'text-ds-subtle')).toBe('text-ds-subtle');
    expect(cn('bg-white', 'bg-ds-default')).toBe('bg-ds-default');
    expect(cn('border-2', 'border-ds-width-md')).toBe('border-ds-width-md');
    expect(cn('border-gray-200', 'border-ds-default')).toBe(
      'border-ds-default'
    );
    expect(cn('divide-x-2', 'divide-x-ds-width-md')).toBe(
      'divide-x-ds-width-md'
    );
    expect(cn('ring-2', 'ring-ds-width-lg')).toBe('ring-ds-width-lg');
    expect(cn('font-semibold', 'font-ds-weight-medium')).toBe(
      'font-ds-weight-medium'
    );
    expect(cn('font-sans', 'font-ds-mono')).toBe('font-ds-mono');
    expect(cn('hover:bg-gray-100', 'hover:bg-ds-subtle')).toBe(
      'hover:bg-ds-subtle'
    );
  });
});
