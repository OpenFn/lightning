import { act, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { StrictMode, useEffect, useState } from 'react';
import { describe, expect, onTestFinished, test, vi } from 'vitest';

import { designSystemPage } from '#/design-system/page';
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

describe('a page drawn before the LiveView joins', () => {
  test('stays mounted, with its state, when the hook takes it over', async () => {
    let mounts = 0;
    const Counter = ({ onGo }: { onGo: () => Promise<void> }) => {
      const [clicks, setClicks] = useState(0);
      useEffect(() => {
        mounts += 1;
      }, []);
      return (
        <>
          <button onClick={() => setClicks(clicks + 1)}>{clicks} clicks</button>
          <button onClick={() => void onGo()}>Go</button>
        </>
      );
    };

    const el = document.createElement('div');
    el.setAttribute('phx-hook', 'ReactComponent');
    el.setAttribute('data-react-name', 'CounterPage');
    el.setAttribute('data-react-file', '/assets/js/counter.js');
    el.setAttribute('data-props', '{}');
    document.body.append(el);
    onTestFinished(() => el.remove());

    // The module loads with the HTML and draws the page from data-props
    act(() => {
      designSystemPage('CounterPage', Counter, ['/counter'], (_, actions) => ({
        onGo: () => actions.send('go'),
      }));
    });
    await userEvent.click(screen.getByRole('button', { name: '0 clicks' }));
    const before = mounts;

    // Then the LiveView joins and the hook mounts on the same container
    const pushEvent = vi.fn().mockResolvedValue({});
    const execNewMounted = vi.fn();
    const hook = Object.create(ReactComponent);
    Object.assign(hook, {
      el,
      pushEvent,
      pushEventTo: vi.fn(),
      handleEvent: vi.fn(),
      removeHandleEvent: vi.fn(),
      liveSocket: { execJS: vi.fn() },
      __view: () => ({
        id: 'v',
        liveSocket: { requestDOMUpdate: (cb: () => void) => cb() },
        execNewMounted,
        componentID: () => null,
      }),
    });
    act(() => {
      hook.mounted();
    });
    onTestFinished(() => {
      act(() => {
        hook._unmount();
      });
    });

    expect(mounts).toBe(before);
    expect(execNewMounted).toHaveBeenCalledTimes(1);
    expect(
      screen.getByRole('button', { name: '1 clicks' })
    ).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Go' }));
    expect(pushEvent).toHaveBeenCalledWith('go', {});
  });
});
