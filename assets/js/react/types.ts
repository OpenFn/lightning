import type { View } from 'phoenix_live_view';

import type * as ReactDOMClient from 'react-dom/client';

import type { PhoenixHook } from '#/hooks/PhoenixHook';

import type { SlotProps } from '#/react/components';

export type ReactHookedElement = HTMLScriptElement & {
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

export type ReactComponentHook<Props = {}> = PhoenixHook<
  {
    /** This Phoenix component's LiveView */
    view: View;

    /** The JavaScript file containing the code for this React component */
    file: string;

    /** The React component's name */
    name: string;

    /** The [React component](https://react.dev/learn/your-first-component) that will actually be rendered */
    Component: React.ComponentType<Props>;

    /** The [React root](https://react.dev/reference/react-dom/client/createRoot) */
    root: ReactDOMClient.Root | undefined;

    /** The [React portal](https://react.dev/reference/react-dom/createPortal) */
    portal: React.ReactPortal | undefined;

    /** The containing React component's `ViewHook` instance */
    containerComponentHook: ReactComponentHook | null | undefined;

    /** The DOM element React will use to mount its root or portal into */
    containerEl: ReactContainerElement;

    /**
     * The React component's current [props](https://react.dev/learn/passing-props-to-a-component).
     * `undefined` signifies no initialization, `null` just means that there are
     * currently no props for this React component (which is perfectly valid).
     */
    props: Props;

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
    children?: Set<React.ReactElement> | null;

    /**
     * `Slot` components with display names, easier debugging in the React devtools
     */
    slots: Map<string, React.FunctionComponent<SlotProps>>;

    /** Set the React component's current props and re-render */
    setProps(): void;

    /**
     * Add a child element to be rendered as one of this React component's children
     *
     * Intended to be used to add portal elements
     */
    addChild(child: React.ReactElement): void;

    /**
     * Remove a child element to be rendered as one of this React component's children
     *
     * Intended to be used to add portal elements
     */
    removeChild(child: React.ReactElement): void;

    /** Subscribe to updates to this React component's props */
    subscribe(onPropsChange: () => void): () => void;

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
