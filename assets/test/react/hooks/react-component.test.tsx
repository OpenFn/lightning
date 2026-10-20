import { render, screen } from '@testing-library/react';
import { StrictMode } from 'react';
import { describe, expect, onTestFinished, test, vi } from 'vitest';

import { Boundary } from '#/react/components';
import { HeexReactComponent } from '#/react/hooks/heex-react-component';
import { ReactComponent } from '#/react/hooks/react-component';

describe.each([
  ['ReactComponent', ReactComponent],
  ['HeexReactComponent', HeexReactComponent],
])('%s _onBoundary', (name, base) => {
  test('mounts once under StrictMode', () => {
    const execNewMounted = vi.fn();
    const hook = Object.create(base);
    hook.__view = () => ({
      id: 'v',
      liveSocket: { requestDOMUpdate: (cb: () => void) => cb() },
      execNewMounted,
    });
    hook._id = `${name}-id`;
    hook._beforeUnmountCallbacks = new Set();
    // Unregisters the id from the shared root store, so another test can reuse it
    onTestFinished(() => hook._beforeUnmount());

    render(
      <StrictMode>
        <Boundary ref={hook._onBoundary.bind(hook)}>
          <span />
        </Boundary>
      </StrictMode>
    );

    expect(execNewMounted).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('alert')).toBeNull();
  });
});
