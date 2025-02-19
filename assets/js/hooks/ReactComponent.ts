import invariant from 'tiny-invariant';
import React, { Suspense, StrictMode } from 'react';
import ReactDOM from 'react-dom/client';
import type { Channel } from 'phoenix';
import { ErrorBoundary } from 'react-error-boundary';

import { replaceEqualDeep } from '../../vendor/replace-equal-deep';

import type { PhoenixHook } from './PhoenixHook';

const reactContainer = (
  el: Element | null
): el is HTMLElement & {
  readonly dataset: { reactContainer: string };
} => el instanceof HTMLElement && typeof el.dataset.reactContainer === 'string';

const phxUpdateIgnore = (
  el: HTMLElement
): el is HTMLElement & {
  readonly attributes: {
    [index: `${number & {}}`]: { name: 'phx-update'; value: 'ignore' };
  };
} =>
  Boolean(
    Array.from(el.attributes).find(
      attr => attr.name === 'phx-update' && attr.value === 'ignore'
    )
  );

export const ReactComponent = {
  mounted() {
    invariant(this.el.id != null, this.errorMsg('Missing `id` attribute!'));
    invariant(
      this.el instanceof HTMLScriptElement,
      this.errorMsg('Element is not a `script`!')
    );
    invariant(
      this.el.type === 'application/json',
      this.errorMsg('Script element `type` is not `application/json`!')
    );
    invariant(
      this.el.dataset.reactName,
      this.errorMsg('Missing `data-react-name` attribute!')
    );
    invariant(
      this.el.dataset.reactFile,
      this.errorMsg('Missing `data-react-file` attribute!')
    );
    invariant(
      reactContainer(this.el.nextElementSibling) &&
        this.el.nextElementSibling.dataset.reactContainer === this.el.id,
      this.errorMsg(`Missing React container element!`)
    );
    invariant(
      phxUpdateIgnore(this.el.nextElementSibling),
      this.errorMsg(
        `React container element not configured to ignore LiveView updates!`
      )
    );

    this.file = this.el.dataset.reactFile;
    this.name = this.el.dataset.reactName;
    this.containerEl = this.el.nextElementSibling;
    this.Component = this.createLazyComponent();
    this.createRoot();
    this.render();
  },

  updated() {
    this.render();
  },

  beforeDestroy() {
    this.unmount();
  },

  createLazyComponent(): React.LazyExoticComponent<React.ComponentType<{}>> {
    // Lazy-load the Component on demand during rendering
    return React.lazy(async () => ({ default: await this.loadComponent() }));
  },

  async loadComponent(): Promise<React.ComponentType<{}>> {
    const module = await import(this.file);
    invariant(
      ('default' in module && module.default != null) ||
        (this.name in module && module[this.name] != null),
      this.errorMsg(`No suitable export found in file \`${this.file}\`!`)
    );
    return module[this.name] ?? module.default;
  },

  setProps() {
    // TODO: Wrap `JSON.parse` in a try/catch, or just let it throw?
    invariant(
      this.el.textContent != null,
      this.errorMsg('No content in script tag!')
    );
    const props = JSON.parse(this.el.textContent) ?? null;
    invariant(typeof props === 'object', 'Invalid props value!');
    this.props = replaceEqualDeep(this.props, props);
  },

  // TODO: Check whether there's a React context root that we should portal into
  // instead, so that this component is part of that React application
  createRoot() {
    invariant(this.errorMsg('React root already created!'));
    this.root = ReactDOM.createRoot(this.containerEl, {
      identifierPrefix: this.el.id,
      // TODO: error handling
      onRecoverableError() {},
    });
  },

  render() {
    this.setProps();
    invariant(this.root, this.errorMsg('No React root!'));
    invariant(this.props !== undefined, this.errorMsg('No props to render!'));
    this.root.render(
      React.createElement(
        StrictMode,
        null,
        React.createElement(
          ErrorBoundary,
          null,
          React.createElement(
            Suspense,
            null,
            React.createElement(this.Component, this.props)
          )
        )
      )
    );
  },

  unmount() {
    invariant(this.root, this.errorMsg('No React root!'));
    this.root.unmount();
  },

  errorMsg(str: string): string {
    return (
      str +
      '\n' +
      [
        'In `ReactComponent` hook',
        this.name != null && `name: \`${this.name}\``,
        this.el.id != null && `id: \`${this.el.id}\``,
      ]
        .filter(Boolean)
        .join(', ') +
      '.'
    );
  },
} as PhoenixHook<
  {
    file: string;
    name: string;
    Component: React.ComponentType;
    root: ReactDOM.Root | undefined;
    containerEl: HTMLElement & {
      readonly attributes: {
        [index: `${number & {}}`]: { name: 'phx-update'; value: 'ignore' };
      };
      readonly dataset: { reactContainer: string };
    };
    /** `undefined` signifies no initialization, null just means no props */
    props: {} | null | undefined;
    channel: Channel;
    createLazyComponent(): React.LazyExoticComponent<React.ComponentType<{}>>;
    loadComponent(): Promise<React.ComponentType<{}>>;
    setProps(): void;
    createRoot(): void;
    render(): void;
    unmount(): void;
    errorMsg(str: string): string;
  },
  {
    reactFile: string | undefined;
    reactName: string | undefined;
  },
  HTMLScriptElement & {
    type: 'application/json';
  }
>;
