
import { render } from '@testing-library/react';
import type React from 'react';
import { describe, expect, test, vi } from 'vitest';

import { SessionContext } from '../../../js/collaborative-editor/contexts/SessionProvider';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreProvider } from '../../../js/collaborative-editor/contexts/StoreProvider';

vi.mock('../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: () => ({ provider: null, ydoc: null, isConnected: false }),
}));

function flagSeenByTheStore(experimentalFeatures: boolean) {
  let seen: boolean | undefined;

  const Probe = () => (
    <StoreContext.Consumer>
      {stores => {
        seen = stores?.sessionContextStore.getSnapshot()
          .experimentalFeaturesEnabled;
        return null;
      }}
    </StoreContext.Consumer>
  );

  render(
    <SessionContext.Provider
      value={
        {
          sessionStore: null,
          isNewWorkflow: false,
          experimentalFeatures,
        } as unknown as React.ContextType<typeof SessionContext>
      }
    >
      <StoreProvider>
        <Probe />
      </StoreProvider>
    </SessionContext.Provider>
  );

  return seen;
}

describe('StoreProvider seeds the experimental flag', () => {
  test('carries it through when the page says the flag is on', () => {
    expect(flagSeenByTheStore(true)).toBe(true);
  });

  test('stays off when the page says so', () => {
    expect(flagSeenByTheStore(false)).toBe(false);
  });
});
