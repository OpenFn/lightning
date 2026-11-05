import { createContext } from 'react';
import { describe, expect, test } from 'vitest';

import { getComponentName } from '#/react/lib';

describe('getComponentName', () => {
  test('names a context provider and consumer after the context', () => {
    const Theme = createContext('light');
    Theme.displayName = 'Theme';

    expect(getComponentName(Theme.Provider)).toBe('Theme.Provider');
    expect(getComponentName(Theme.Consumer)).toBe('Theme.Consumer');
  });
});
