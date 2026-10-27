import { fireEvent, render, screen } from '@testing-library/react';
import { StrictMode, useState } from 'react';
import { describe, expect, onTestFinished, test, vi } from 'vitest';

import { Boundary } from '#/react/components';
import { HeexReactComponent } from '#/react/hooks/heex-react-component';
import { ReactComponent } from '#/react/hooks/react-component';
import { RootObserver } from '#/react/lib';

describe.each([
  ['ReactComponent', ReactComponent],
  ['HeexReactComponent', HeexReactComponent],
])('%s _onBoundary', (name, base) => {
  const setup = (
    id: string,
    requestDOMUpdate = (cb: () => void) => {
      cb();
    }
  ) => {
    const execNewMounted = vi.fn();
    const registered = vi.spyOn(RootObserver.prototype, 'mounted');
    onTestFinished(() => registered.mockRestore());

    const hook = Object.create(base);
    hook.__view = () => ({
      id: 'v',
      liveSocket: { requestDOMUpdate },
      execNewMounted,
    });
    hook._id = `${name}-${id}`;
    hook._beforeUnmountCallbacks = new Set();
    // Unregisters the id from the shared root store, so another test can reuse it
    onTestFinished(() => hook._beforeUnmount());

    return { hook, execNewMounted, registered };
  };

  test('registers once under StrictMode', () => {
    const { hook, execNewMounted, registered } = setup('strict');

    render(
      <StrictMode>
        <Boundary ref={hook._onBoundary.bind(hook)}>
          <span />
        </Boundary>
      </StrictMode>
    );

    expect(execNewMounted).toHaveBeenCalled();
    expect(registered).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('alert')).toBeNull();
  });

  test('mounts LiveView hooks again after an error boundary retry', () => {
    const { hook, execNewMounted, registered } = setup('retry');
    const consoleError = vi
      .spyOn(console, 'error')
      .mockImplementation(() => {});
    onTestFinished(() => consoleError.mockRestore());
    let broken = false;

    const Child = () => {
      const [, rerender] = useState(0);
      if (broken) throw new Error('broken');
      return (
        <button type="button" onClick={() => rerender(n => n + 1)}>
          Break
        </button>
      );
    };

    render(
      <Boundary ref={hook._onBoundary.bind(hook)}>
        <Child />
      </Boundary>
    );
    expect(execNewMounted).toHaveBeenCalledTimes(1);

    broken = true;
    fireEvent.click(screen.getByRole('button', { name: 'Break' }));
    expect(screen.getByRole('alert')).toBeInTheDocument();

    broken = false;
    fireEvent.click(screen.getByRole('button', { name: 'Retry' }));

    expect(screen.queryByRole('alert')).toBeNull();
    expect(execNewMounted).toHaveBeenCalledTimes(2);
    expect(registered).toHaveBeenCalledTimes(1);
  });

  test('skips a deferred mount once React has detached the element', () => {
    const pending: (() => void)[] = [];
    const { hook, execNewMounted, registered } = setup('deferred', cb => {
      pending.push(cb);
    });

    const { unmount } = render(
      <StrictMode>
        <Boundary ref={hook._onBoundary.bind(hook)}>
          <span />
        </Boundary>
      </StrictMode>
    );
    unmount();
    pending.forEach(cb => cb());

    expect(execNewMounted).not.toHaveBeenCalled();
    expect(registered).not.toHaveBeenCalled();
  });

  test('mounts once under StrictMode while LiveView is busy', () => {
    const pending: (() => void)[] = [];
    const { hook, execNewMounted, registered } = setup(
      'deferred-strict',
      cb => {
        pending.push(cb);
      }
    );

    render(
      <StrictMode>
        <Boundary ref={hook._onBoundary.bind(hook)}>
          <span />
        </Boundary>
      </StrictMode>
    );
    pending.forEach(cb => cb());

    expect(execNewMounted).toHaveBeenCalledTimes(1);
    expect(registered).toHaveBeenCalledTimes(1);
  });
});
