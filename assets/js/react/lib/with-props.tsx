import { StrictMode, useSyncExternalStore } from 'react';

import { Boundary } from '#/react/components/Boundary';
import type { Portals } from '#/react/types';

import { mergeChildren } from './merge-children';
import { renderPortals } from './render-portals';

interface ActionProps {
  pushEvent: (name: string, payload: Record<string, unknown>) => unknown;
  pushEventTo: (
    name: string,
    payload: Record<string, unknown>,
    callback?: (response: unknown) => void
  ) => unknown;
  handleEvent: (
    name: string,
    callback: (payload: unknown) => void
  ) => () => void;
  el: HTMLElement;
  containerEl: HTMLElement;
  navigate: (path: string, options?: { replace?: boolean }) => void;
  redirect: (path: string, options?: { replace?: boolean }) => void;
}

export type WithActionProps<T = Record<string, unknown>> =
  React.FunctionComponent<React.PropsWithChildren<ActionProps & T>>;

/** Where a hook's component gets its props, portals and actions. */
export interface PropsSource {
  subscribe: (onChange: () => void) => () => void;
  getProps: () => object | null;
  getPortals: () => Portals;
  actions: ActionProps;
  /** Turns slot props into elements (`renderSlots`); a page drawn before the LiveView joins has none. */
  withSlots?: (props: object | null) => object | null;
}

/**
 * Renders `Component` with the props and portals from `source`, using
 * [`useSyncExternalStore`](https://react.dev/reference/react/useSyncExternalStore)
 * to re-render when they change.
 *
 * It is one component for every hook, so a root drawn before the hook
 * mounted keeps its tree, and its state, when the hook re-renders it with
 * its own source.
 */
export const WithProps = ({
  Component,
  source,
}: {
  Component: React.ComponentType<object>;
  source: PropsSource;
}) => {
  const raw = useSyncExternalStore(source.subscribe, source.getProps);
  const props = source.withSlots ? source.withSlots(raw) : raw;
  const portals = useSyncExternalStore(source.subscribe, source.getPortals);
  const { actions } = source;
  // Any component a hook names takes the hook's props and actions.
  const Target = Component as React.ComponentType<Record<string, unknown>>;
  return (
    <Target
      {...props}
      pushEvent={actions.pushEvent}
      pushEventTo={actions.pushEventTo}
      handleEvent={actions.handleEvent}
      navigate={actions.navigate}
      redirect={actions.redirect}
      el={actions.el}
      containerEl={actions.containerEl}
    >
      {mergeChildren(
        (props !== null &&
          'children' in props &&
          props.children) as React.ReactNode,
        renderPortals(portals)
      )}
    </Target>
  );
};

/**
 * What a hook renders into its root. A page drawn before the LiveView joins
 * renders the same tree, so the hook adopts the root without remounting it.
 */
export const rootTree = (
  Component: React.ComponentType<object>,
  source: PropsSource,
  onBoundary?: (element: HTMLDivElement | null) => void
) => (
  // Find common bugs early in development with [`StrictMode`](https://react.dev/reference/react/StrictMode)
  <StrictMode>
    <Boundary ref={onBoundary}>
      <WithProps Component={Component} source={source} />
    </Boundary>
  </StrictMode>
);
