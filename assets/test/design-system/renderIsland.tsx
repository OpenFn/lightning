import { render } from '@testing-library/react';
import type { ComponentType } from 'react';
import { vi } from 'vitest';

import { Toaster } from '../../js/design-system/flash';
import type { IslandProps } from '../../js/design-system/page';

/**
 * Renders a design-system island as the `ReactComponent` hook does, with
 * `props` as its `data-props`. Name the wrapper's `Props`
 * (`renderIsland<Props>(...)`) so the fixture is checked against what the
 * LiveView sends. Every push replies with `reply`; chain `mockResolvedValueOnce`
 * on the returned `pushEvent` for more. `setProps` draws the LiveView's next
 * props, as a patch brings them. The page's toasts go to the layout's
 * toaster, which app.js mounts; it is drawn beside the island here.
 */
export const renderIsland = <Props = never,>(
  Island: ComponentType<IslandProps>,
  props: NoInfer<Props>,
  { reply = {} }: { reply?: unknown } = {}
) => {
  const pushEvent = vi.fn<IslandProps['pushEvent']>().mockResolvedValue(reply);
  const handleEvent = vi.fn<IslandProps['handleEvent']>(() => () => {});
  const navigate = vi.fn<IslandProps['navigate']>();
  const redirect = vi.fn<IslandProps['redirect']>();
  const island = (next: Props) => (
    <>
      <Island
        data-props={JSON.stringify(next)}
        pushEvent={pushEvent}
        handleEvent={handleEvent}
        navigate={navigate}
        redirect={redirect}
      />
      <Toaster />
    </>
  );
  const result = render(island(props));
  const setProps = (next: NoInfer<Props>) => result.rerender(island(next));
  return { ...result, pushEvent, handleEvent, navigate, redirect, setProps };
};
