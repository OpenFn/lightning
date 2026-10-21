import { ToastProvider } from '@openfn/ui/components/Toast.tsx';
import { RouterProvider } from '@openfn/ui/routing/router.tsx';
import { RequestError } from '@openfn/ui/utils/errors.ts';
import { useEffect, useMemo, useRef } from 'react';

import { registerComponent, replaceEqualDeep } from '#/react/lib';

import { useLiveViewRouter } from './router';

/**
 * The kit: how a design-system page talks to its LiveView. Only this file
 * and `router.ts` know about LiveView; pages see these four functions.
 */
export interface PageActions {
  /**
   * Pushes an event and waits for the reply. Rejects with a `RequestError`
   * when the reply is `{error, fieldErrors}` (see `reply_error/2`), when the
   * LiveView disconnects, and after 30 s, because LiveView's own promise
   * never settles on a crash or timeout.
   */
  send: (event: string, payload?: Record<string, unknown>) => Promise<void>;
  /** Like `send`, but resolves with the reply. One-time secrets arrive this way. */
  request: <T = Record<string, unknown>>(
    event: string,
    payload?: Record<string, unknown>
  ) => Promise<T>;
  /** Listens for a `push_event` from the LiveView. Returns the unsubscribe. */
  subscribe: <T = unknown>(
    event: string,
    callback: (payload: T) => void
  ) => () => void;
  /** Patches when the path is one of this LiveView's routes; live-redirects otherwise. */
  navigate: (path: string, opts?: { replace?: boolean }) => void;
}

type Go = (path: string, opts?: { replace?: boolean }) => void;

/** What the `ReactComponent` hook passes to the island. */
interface IslandProps {
  'data-props': string;
  pushEvent: (
    name: string,
    payload?: Record<string, unknown>
  ) => Promise<unknown>;
  handleEvent: (
    name: string,
    callback: (payload: unknown) => void
  ) => () => void;
  navigate: Go;
  redirect: Go;
}

interface Reply {
  error?: string;
  fieldErrors?: Record<string, string[]>;
}

const REPLY_TIMEOUT = 30_000;

const createActions = (
  pushEvent: IslandProps['pushEvent'],
  handleEvent: IslandProps['handleEvent'],
  navigate: Go
) => {
  const pending = new Set<(reason: Error) => void>();

  const request = async <T,>(
    event: string,
    payload: Record<string, unknown> = {}
  ): Promise<T> => {
    let fail!: (reason: Error) => void;
    const failed = new Promise<never>((_resolve, reject) => {
      fail = reject;
    });
    pending.add(fail);
    const timer = setTimeout(
      () =>
        fail(new RequestError('The server did not answer. Please try again.')),
      REPLY_TIMEOUT
    );
    try {
      const reply = await Promise.race([pushEvent(event, payload), failed]);
      // A handler that redirects replies with null; that is success.
      const { error, fieldErrors } = (reply ?? {}) as Reply;
      if (error) throw new RequestError(error, { fieldErrors });
      return reply as T;
    } finally {
      pending.delete(fail);
      clearTimeout(timer);
    }
  };

  const actions: PageActions = {
    request,
    send: (event, payload) => request(event, payload).then(() => undefined),
    subscribe: (event, callback) =>
      handleEvent(event, callback as (payload: unknown) => void),
    navigate,
  };

  const disconnect = () => {
    for (const fail of pending)
      fail(new RequestError('Connection lost. Please try again.'));
  };

  return { actions, disconnect };
};

/**
 * Wraps a props-only design-system page as a LiveView island. Props come
 * from one `data-props` JSON attribute, parsed when the string changes and
 * structurally shared so unchanged records keep their identity. `useProps`
 * turns them plus the actions into the page's props; it runs as a hook, so
 * it may keep UI state (a secret shown once, a draft).
 */
export const designSystemPage = <Props, PageProps extends object>(
  /** The island's name: the module's export and the LiveView's `name`. */
  name: string,
  Page: React.ComponentType<PageProps>,
  routes: string[],
  useProps: (props: Props, actions: PageActions) => PageProps
) => {
  const Island = ({
    'data-props': json,
    pushEvent,
    handleEvent,
    navigate,
    redirect,
  }: IslandProps) => {
    const previous = useRef<Props>(undefined);
    const props = useMemo(() => {
      const next = replaceEqualDeep(
        previous.current,
        JSON.parse(json) as Props
      );
      previous.current = next;
      return next;
    }, [json]);

    const router = useLiveViewRouter({ navigate, redirect }, routes);
    const { actions, disconnect } = useMemo(
      () =>
        createActions(pushEvent, handleEvent, (path, opts) =>
          router.navigate(path, opts)
        ),
      [pushEvent, handleEvent, router]
    );

    // LiveView announces a lost connection on the window; settle what's waiting.
    useEffect(() => {
      const onLoading = (event: Event) => {
        if ((event as CustomEvent<{ kind?: string }>).detail?.kind === 'error')
          disconnect();
      };
      window.addEventListener('phx:page-loading-start', onLoading);
      return () =>
        window.removeEventListener('phx:page-loading-start', onLoading);
    }, [disconnect]);

    const pageProps = useProps(props, actions);

    return (
      <RouterProvider value={router}>
        <ToastProvider>
          <Page {...pageProps} />
        </ToastProvider>
      </RouterProvider>
    );
  };
  Island.displayName = `designSystemPage(${name})`;
  // The module is loaded with the page, so the hook finds the island here
  // and renders it before the LiveView reports itself connected.
  registerComponent(name, Island as unknown as React.ComponentType<object>);
  return Island;
};
