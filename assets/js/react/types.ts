import type { View } from 'phoenix_live_view';

import type * as ReactDOMClient from 'react-dom/client';

import type { PhoenixHook } from '#/hooks/PhoenixHook';

export type ReactHookedElement = HTMLElement & {
  type: 'application/json';
  readonly attributes: {
    [index: `${number & {}}`]: { name: 'phx-hook'; value: 'ReactComponent' };
  };
  readonly dataset: { reactName: string; reactFile: string };
};

export type ReactContainerElement = HTMLElement & {
  readonly attributes: {
    [index: `${number & {}}`]: { name: 'phx-update'; value: 'ignore' };
  };
  readonly dataset: { reactContainer: string };
};

export type Portals = Map<
  string,
  [container: Element | DocumentFragment, children: React.ReactNode]
>;

export type ReactComponentHook<Props = object> = PhoenixHook<
  {
    /** This Phoenix component's LiveView */
    view: View;

    /** The JavaScript file containing the code for this React component */
    file: string;

    /** The React component's name */
    name: string;

    /** The [React component](https://react.dev/learn/your-first-component) that will actually be rendered */
    Component: React.ComponentType<t.EmptyObject>;

    /** The [React root](https://react.dev/reference/react-dom/client/createRoot) */
    root: ReactDOMClient.Root | undefined;

    /** The containing React component's `ViewHook` instance */
    containerComponentHook: ReactComponentHook | null | undefined;

    /** The DOM element React will use to mount its root or portal into */
    containerEl: ReactContainerElement;

    /**
     * The React component's current [props](https://react.dev/learn/passing-props-to-a-component).
     * `undefined` signifies no initialization, `null` just means that there are
     * currently no props for this React component (which is perfectly valid).
     */
    props?: Props | undefined;

    /**
     * Currently subscribed listeners to props updates
     *
     * This should only contain our own React component's `onStoreChange`
     * subscription callback.
     */
    listeners: Set<() => void>;

    /**
     * Child React elements
     */
    portals: Portals;

    /** Set the React component's current props and re-render */
    setProps(): void;

    /**
     * Passed to Root and Portal Boundary elements as a callback ref so we know
     * when they've mounted in the DOM.
     */
    onBoundary(element: HTMLDivElement | null): void;

    boundaryMounted: boolean;

    /**
     * Add a portal and re-render.
     */
    addPortal(
      children: React.ReactNode,
      container: Element | DocumentFragment,
      key?: null | string
    ): void;

    /**
     * Remove a portal and re-render.
     */
    removePortal(key: string): void;

    /**
     * Get the current portals.
     */
    getPortals(): Portals;

    /** Subscribe to updates to this React component's props */
    subscribe(onPropsChange: () => void): () => void;

    /** Ask React to re-render the component. Will no-op if props & portals haven't changed */
    rerender(): void;

    /** Get the React component's current props */
    getProps(): Props;

    /** Mount the React component into the container element. */
    mount(): void;

    /** Get a unique key for this instance */
    getKey(): string;

    /** Create a [React root](https://react.dev/reference/react-dom/client/createRoot) on the `containerEl` and render */
    mountRoot(): void;

    /** Create a [React portal](https://react.dev/reference/react-dom/createPortal) on the `containerEl` and render */
    mountPortal(): void;

    /** [Unmount](https://react.dev/reference/react-dom/client/createRoot#root-unmount) the React component, destroying its React tree */
    unmount(): void;

    /** Unmount a React root */
    unmountRoot(): void;

    /** Unmount a React portal */
    unmountPortal(): void;

    /** Add some handy debugging information to a string */
    errorMsg(str: string): string;
  },
  ReactHookedElement['dataset'],
  ReactHookedElement
>;
