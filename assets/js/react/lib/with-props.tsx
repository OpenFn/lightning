import type { View } from 'phoenix_live_view';
import { useSyncExternalStore } from 'react';

import type { Portals } from '#/react/types';

import { getComponentName } from './get-component-name';
import { mergeChildren } from './merge-children';
import { renderPortals } from './render-portals';
import { renderSlots } from './render-slots';

interface ActionProps {
  pushEvent: (name: string, payload: Record<string, unknown>) => void;
  pushEventTo: (
    name: string,
    payload: Record<string, unknown>,
    callback?: (response: unknown) => void
  ) => void;
  handleEvent: (
    name: string,
    callback: (payload: unknown) => void
  ) => () => void;
  el: HTMLElement;
  containerEl: HTMLElement;
  navigate: (path: string) => void;
}

export type WithActionProps<T = Record<string, unknown>> =
  React.FunctionComponent<React.PropsWithChildren<ActionProps & T>>;

/**
 * Use [`useSyncExternalStore`](https://react.dev/reference/react/useSyncExternalStore)
 * to tell the React component to re-render when its props have changed.
 *
 * This especially makes re-rendering components rendered into a parent
 * React container using portals much easier.
 */
export const withProps = <const Props = object,>(
  Component: React.ComponentType<Props>,
  subscribe: (onChange: () => void) => () => void,
  getProps: () => Props,
  getPortals: () => Portals,
  actions: ActionProps,
  view: View,
  cID: number | null = null
): React.FunctionComponent<t.EmptyObject> => {
  const WithProps = () => {
    const props = renderSlots({
      props: useSyncExternalStore(subscribe, getProps),
      view,
      cID,
    });

    const portals = useSyncExternalStore(subscribe, getPortals);
    return (
      <Component
        {...(props as React.JSX.IntrinsicAttributes & Props)}
        pushEvent={actions.pushEvent}
        pushEventTo={actions.pushEventTo}
        handleEvent={actions.handleEvent}
        navigate={actions.navigate}
        el={actions.el}
        containerEl={actions.containerEl}
      >
        {mergeChildren(
          (typeof props === 'object' &&
            props !== null &&
            'children' in props &&
            props.children) as React.ReactNode,
          renderPortals(portals)
        )}
      </Component>
    );
  };

  // Easier debugging in the React devtools
  WithProps.displayName = `withProps(${getComponentName(Component)})`;

  return WithProps;
};
