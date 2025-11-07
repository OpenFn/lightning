import type { View } from 'phoenix_live_view';
import type * as ReactDOMClient from 'react-dom/client';

import type { PhoenixHook } from '#/hooks/PhoenixHook';

export type ReactHookedElement = HTMLElement & {
  type: 'application/json';
  readonly attributes: {
    [index: `${number & {}}`]: { name: 'phx-hook'; value: 'ReactComponent' };
  };
  readonly dataset: {
    reactName: string;
    reactFile: string;
    reactId: string | undefined;
    reactPortalTarget: string | undefined;
  };
};

export type ReactContainerElement = HTMLElement & {
  readonly attributes: {
    [index: `${number & {}}`]: { name: 'phx-update'; value: 'ignore' };
  };
  readonly dataset: { reactContainer: string };
};

export type Portals = Map<
  string,
  [container: Element | DocumentFragment, render: () => React.ReactNode]
>;

export type ReactComponentHook<Props = object> = PhoenixHook<
  {
    /** The JavaScript file containing the code for this React component */
    _file: string;

    /** The React component's name */
    _name: string;

    /** The *React* instance id, used by `ReactComponentHook`s to find each other */
    _id?: string | undefined;

    /** The React instance id to portal into */
    _portalTarget?: string | undefined;

    /** The [React component](https://react.dev/learn/your-first-component) that will actually be rendered */
    _Component: React.ComponentType<t.EmptyObject>;

    /** The [React root](https://react.dev/reference/react-dom/client/createRoot) */
    _root: ReactDOMClient.Root | undefined;

    /** The portal target React component's `ViewHook` instance */
    _portalHook: ReactComponentHook | null | undefined;

    /** The DOM element React will use to mount its root or portal into */
    _containerEl: ReactContainerElement;

    /**
     * The React component's current [props](https://react.dev/learn/passing-props-to-a-component).
     * `undefined` signifies no initialization, `null` just means that there are
     * currently no props for this React component (which is perfectly valid).
     */
    _props?: Props | undefined;

    /**
     * Currently subscribed listeners to props updates
     *
     * This should only contain our own React component's `onStoreChange`
     * subscription callback.
     */
    _listeners: Set<() => void>;

    /**
     * Child React elements
     */
    _portals: Portals;

    /** Set the React component's current props and re-render */
    _setProps(): void;

    /**
     * Passed to Root and Portal Boundary elements as a callback ref so we know
     * when they've mounted in the DOM.
     */
    _onBoundary(element: HTMLDivElement | null): void;

    _boundaryMounted: boolean;

    /**
     * Add a portal and re-render.
     */
    addPortal(
      render: () => React.ReactNode,
      container: Element | DocumentFragment,
      key: string
    ): void;

    /**
     * Remove a portal and re-render.
     */
    removePortal(key: string): void;

    /**
     * Get the current portals.
     */
    _getPortals(): Portals;

    /** Subscribe to updates to this React component's props */
    _subscribe(onPropsChange: () => void): () => void;

    /** Ask React to re-render the component. Will no-op if props & portals haven't changed */
    _rerender(): void;

    /** Get the React component's current props */
    _getProps(): Props;

    /** Mount the React component into the container element. */
    _mount(): void;

    /** Get a unique key for this instance */
    _getKey(): string;

    /** Create a [React root](https://react.dev/reference/react-dom/client/createRoot) on the `containerEl` and render */
    _mountRoot(): void;

    /** Create a [React portal](https://react.dev/reference/react-dom/createPortal) on the `containerEl` and render */
    _mountPortal(): void;

    /** [Unmount](https://react.dev/reference/react-dom/client/createRoot#root-unmount) the React component, destroying its React tree */
    _unmount(): void;

    /** Before unmount callbacks */
    _beforeUnmountCallbacks: Set<() => void>;

    /** Register a function to be called before  */
    _onBeforeUnmount(callback: () => void): void;

    /** Run any before unmount callbacks */
    _beforeUnmount(): void;

    /** Unmount a React root */
    _unmountRoot(): void;

    /** Unmount a React portal */
    _unmountPortal(): void;

    /** Add some handy debugging information to a string */
    _errorMsg(str: string): string;
  },
  ReactHookedElement['dataset'],
  ReactHookedElement
>;

export type RootMessage =
  | { type: 'mounted'; hook: ReactComponentHook }
  | { type: 'beforeUnmount' };
