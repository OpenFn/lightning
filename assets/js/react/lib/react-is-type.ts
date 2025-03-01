import {
  Component,
  type Fragment as ReactFragment,
  type Profiler as ReactProfiler,
  type StrictMode as ReactStrictMode,
  type Suspense as ReactSuspense,
} from 'react';

import {
  ContextConsumer,
  ContextProvider,
  ForwardRef,
  Fragment,
  Lazy,
  Memo,
  Portal,
  Profiler,
  StrictMode,
  Suspense,
} from 'react-is';

export const isClass = (
  type: unknown
): type is React.ComponentClass<unknown, unknown> => type instanceof Component;

export const isFunction = (
  type: unknown
): type is React.FunctionComponent<unknown> => typeof type === 'function';

export const isContextConsumer = (
  type: unknown
): type is React.Consumer<unknown> =>
  typeof type === 'object' &&
  type !== null &&
  '$$typeof' in type &&
  type.$$typeof === ContextConsumer;

export const isContextProvider = (
  type: unknown
): type is React.ProviderExoticComponent<unknown> =>
  typeof type === 'object' &&
  type !== null &&
  '$$typeof' in type &&
  type.$$typeof === ContextProvider;

export const isForwardRef = (
  type: unknown
): type is React.ForwardRefExoticComponent<unknown> =>
  typeof type === 'object' &&
  type !== null &&
  '$$typeof' in type &&
  type.$$typeof === ForwardRef;

export const isLazy = (
  type: unknown
): type is React.LazyExoticComponent<React.ComponentType<unknown>> =>
  typeof type === 'object' &&
  type !== null &&
  '$$typeof' in type &&
  type.$$typeof === Lazy;

export const isMemo = (
  type: unknown
): type is React.MemoExoticComponent<React.ComponentType<unknown>> =>
  typeof type === 'object' &&
  type !== null &&
  '$$typeof' in type &&
  type.$$typeof === Memo;

export const isFragment = (type: any): type is typeof ReactFragment =>
  type === Fragment;

export const isProfiler = (type: any): type is typeof ReactProfiler =>
  type === Profiler;

export const isPortal = (type: any): type is React.ReactPortal =>
  type === Portal;

export const isStrictMode = (type: any): type is typeof ReactStrictMode =>
  type === StrictMode;

export const isSuspense = (type: any): type is typeof ReactSuspense =>
  type === Suspense;

export const isSymbol = (
  type: any
): type is
  | typeof ReactFragment
  | React.ReactPortal
  | typeof ReactProfiler
  | typeof ReactStrictMode
  | typeof ReactSuspense =>
  [Fragment, Portal, Profiler, StrictMode, Suspense].includes(type);

export const isTypeOf = (type: any): type is React.ExoticComponent<unknown> =>
  typeof type === 'object' &&
  type !== null &&
  '$$typeof' in type &&
  [ContextConsumer, ContextProvider, ForwardRef, Memo, Lazy].includes(
    type.$$typeof
  );

export const isExotic = (type: any): type is React.ExoticComponent<unknown> =>
  isSymbol(type) || isTypeOf(type);

export const isNamedExotic = (
  type: any
): type is React.NamedExoticComponent<unknown> =>
  isTypeOf(type) && 'displayName' in type;

export const isIntrinsic = (
  type: any
): type is keyof React.JSX.IntrinsicElements => typeof type === 'string';
