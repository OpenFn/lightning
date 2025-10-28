import type { ViewHook, ViewHookInternal } from 'phoenix_live_view';
export type CallbackRef = { event: string; callback: (payload: any) => any };

interface PhoenixHookInternal<
  Dataset extends DOMStringMap = {},
  El extends HTMLElement = HTMLElement,
> extends Omit<ViewHookInternal, 'el'> {
  el: El & {
    readonly dataset: Dataset;
  };
  handleEvent<T extends object = {}>(
    event: string,
    callback: (payload: T) => void
  ): CallbackRef;
  removeHandleEvent(ref: CallbackRef): void;
  pushEvent<P extends object = {}, R = any>(
    event: string,
    payload: P,
    onReply?: (reply: R, ref: number) => void
  ): void;
  pushEventTo<P extends object = {}, R = any>(
    selectorOrTarget: string | HTMLElement,
    event: string,
    payload: P,
    onReply?: (reply: R, ref: number) => void
  ): void;
}

type OmitThis<T> = T extends (this: infer _, ...args: any) => any
  ? OmitThisParameter<T>
  : T;

type OmitThisInMethods<T extends object = {}> = {
  [k in keyof T]: OmitThis<T[k]>;
};

type OmitPrivate<T extends object = {}> = {
  [k in keyof T as k extends `_${string}` ? never : k]: T[k];
};

type PhoenixHookInternalThis<
  T extends object = {},
  Dataset extends DOMStringMap = {},
  El extends HTMLElement = HTMLElement,
> = T & PhoenixHookInternal<Dataset, El>;

export type PhoenixHook<
  T extends object = {},
  Dataset extends DOMStringMap = {},
  El extends HTMLElement = HTMLElement,
> = OmitThisInMethods<OmitPrivate<T> & ViewHook<T>> &
  ThisType<PhoenixHookInternalThis<T, Dataset, El>>;

export type GetPhoenixHookInternalThis<T> =
  T extends PhoenixHook<infer S extends object, infer Dataset, infer El>
    ? PhoenixHookInternalThis<S, Dataset, El>
    : never;
