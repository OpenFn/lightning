import { useSyncExternalStore } from 'react';

import { getComponentName } from './get-component-name';

/**
 * Use [`useSyncExternalStore`](https://react.dev/reference/react/useSyncExternalStore)
 * to tell the React component to re-render when its props have changed.
 *
 * This especially makes re-rendering components rendered into a parent
 * React container using portals much easier.
 */
export const withProps = <const Props = {},>(
  Component: React.ComponentType<Props>,
  subscribe: (onPropsChange: () => void) => () => void,
  getProps: () => Props
): React.FunctionComponent<t.EmptyObject> => {
  const WithProps = () => {
    const props = useSyncExternalStore(subscribe, getProps);
    return <Component {...(props as React.JSX.IntrinsicAttributes & Props)} />;
  };

  // Easier debugging in the React devtools
  WithProps.displayName = `withProps(${getComponentName(Component)})`;

  return WithProps;
};
