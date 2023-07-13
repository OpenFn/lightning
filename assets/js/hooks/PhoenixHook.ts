export interface LiveSocket {
  execJS(el: HTMLElement, code: string): void;
  pushHistoryPatch(url: string, type: string, el?: HTMLElement): void;
}

export type PhoenixHook<T = {}, Dataset = {}, El = HTMLElement> = {
  mounted(): void;
  updated(): void;
  liveSocket: LiveSocket;
  el: El & {
    dataset: Dataset;
  };
  destroyed(): void;
  reconnected(): void;
  disconnected(): void;
  handleEvent<T = {}>(eventName: string, callback: (payload: T) => void): void;
  pushEventTo<P = {}, R = any>(
    selectorOrTarget: string | HTMLElement,
    event: string,
    payload: P,
    callback?: (reply: R, ref: any) => void
  ): void;
} & T;
