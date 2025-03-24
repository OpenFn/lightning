import type { Fragment, Profiler, StrictMode, Suspense } from 'react';

import {
  isClass,
  isContextConsumer,
  isContextProvider,
  isForwardRef,
  isFragment,
  isFunction,
  isIntrinsic,
  isLazy,
  isMemo,
  isNamedExotic,
  isPortal,
  isProfiler,
  isStrictMode,
  isSuspense,
} from './react-is-type';

// https://regex101.com/r/oOJW4t/1
const innerMostNameRegex = /([^()]+)\)*$/;

const unwrapName = (name: string): string =>
  name.match(innerMostNameRegex)?.[1] ?? '';

const getContextName = (
  component: React.Consumer<unknown> | React.ProviderExoticComponent<unknown>
): string =>
  (isNamedExotic(component) ? component.displayName : undefined) || 'Context';

const getWrappedName = (
  outerType: React.NamedExoticComponent<unknown>,
  innerType: React.ComponentType<unknown>,
  wrapperName: string
): string => {
  const displayName = outerType.displayName;

  if (displayName) {
    return displayName;
  }

  const functionName = innerType.displayName || innerType.name || '';
  return functionName !== ''
    ? wrapperName + '(' + functionName + ')'
    : wrapperName;
};

export const getComponentName = <const Props = object>(
  type:
    | keyof React.JSX.IntrinsicElements
    | React.ComponentType<Props>
    | React.JSXElementConstructor<Props>
    | React.ForwardRefExoticComponent<Props>
    | React.MemoExoticComponent<React.ComponentType<Props>>
    | React.LazyExoticComponent<React.ComponentType<Props>>
    | React.Consumer<Props>
    | React.ProviderExoticComponent<Props>
    | React.ReactPortal
    | typeof Fragment
    | typeof Profiler
    | typeof StrictMode
    | typeof Suspense,
  options: { fromType?: boolean; unwrap?: boolean } = {}
): string => {
  const name = (() => {
    switch (true) {
      case isClass(type):
      // Fall through
      case isFunction(type): {
        return type.displayName || type.name;
      }
      case isIntrinsic(type): {
        return type;
      }
      case isFragment(type): {
        return 'Fragment';
      }
      case isPortal(type): {
        return 'Portal';
      }
      case isProfiler(type): {
        return 'Profiler';
      }
      case isStrictMode(type): {
        return 'StrictMode';
      }
      case isSuspense(type): {
        return 'Suspense';
      }
      case isForwardRef(type): {
        const { render } = type as typeof type & {
          render: React.FunctionComponent<unknown>;
        };
        return options.fromType
          ? getComponentName(render)
          : getWrappedName(type, render, 'ForwardRef');
      }
      case isMemo(type): {
        return options.fromType
          ? getComponentName(type.type)
          : type.displayName || getComponentName(type.type) || 'Memo';
      }
      case isLazy(type): {
        const lazyComponent = type as typeof type &
          React.NamedExoticComponent<unknown>;
        return lazyComponent.displayName ?? '';
      }
      case isContextConsumer(type): {
        return getContextName(type) + '.Consumer';
      }
      case isContextProvider(type): {
        const { _context } = type as typeof type & {
          _context: React.ExoticComponent<unknown>;
        };
        return getContextName(_context) + '.Provider';
      }
      default: {
        return '';
      }
    }
  })();

  if (!options.unwrap) {
    return name;
  }

  return unwrapName(name);
};
