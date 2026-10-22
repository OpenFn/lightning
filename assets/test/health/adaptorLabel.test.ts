import { describe, expect, test } from 'vitest';

import { adaptorLabel } from '#/health/adaptorLabel';

describe('adaptorLabel', () => {
  test.each([
    ['@openfn/language-http@1.2.3', 'http adaptor'],
    ['@openfn/language-common', 'common adaptor'],
    ['@acme/custom-thing@1.0.0', '@acme/custom-thing adaptor'],
  ])('labels %s as "%s"', (adaptor, label) => {
    expect(adaptorLabel(adaptor)).toBe(label);
  });
});
