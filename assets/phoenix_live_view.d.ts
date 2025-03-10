/* eslint-disable @eslint-community/eslint-comments/disable-enable-pair, @typescript-eslint/no-unused-vars, @typescript-eslint/no-empty-object-type, @typescript-eslint/no-explicit-any */
import { Channel } from 'phoenix';

// Empty export is ecessary to treat this file as a module instead of a script.
// Modules can *augment* upstream type defs, whilst scripts completely override
// upstream typedefs, which is usually not what you want.
export {};

declare module 'phoenix_live_view' {
  interface LiveSocket {
    requestDOMUpdate(callback: () => void): void;

    /** @private */
    bind(events: string[], callback: BindCallback): void;
    /** @private */
    bindClick(eventName: string, bindingName: string, capture: boolean): void;
    /** @private */
    bindClicks(): void;
    /** @private */
    bindForms(): void;
    /** @private */
    binding(kind: string): string;
    /** @private */
    bindNav(): void;
    /** @private */
    bindTopLevelEvents(): void;
    /** @private */
    blurActiveElement(): void;
    /** @private */
    channel(topic: string, params: any): Channel;
    /** @private */
    commitPendingLink(linkRef: number): boolean;
    /** @private */
    debounce(el: HTMLElement, event: Event, callback: any): void;
    /** @private */
    destroyAllViews(): void;
    /** @private */
    destroyViewByEl(el: HTMLElement): void;
    /** @private */
    dropActiveElement(view: View): void;
    /** @private */
    eventMeta(eventName: string, e: Event, targetEl: HTMLElement): object;
    /** @private */
    getActiveElement(): Element;
    /** @private */
    getBindingPrefix(): string;
    /** @private */
    getHookCallbacks(hookName: string): any;
    /** @private */
    getHref(): string;
    /** @private */
    getRootById(id: string): any;
    /** @private */
    getViewByEl(el: HTMLElement): any;
    /** @private */
    hasPendingLink(): boolean;
    /** @private */
    historyPatch(href: string, linkState: string): void;
    /** @private */
    historyRedirect(href: string, linkState: string, flash: string): void;
    /** @private */
    isConnected(): boolean;
    /** @private */
    isPhxView(el: HTMLElement): boolean;
    /** @private */
    isUnloaded(): boolean;
    /** @private */
    joinRootView(
      el: HTMLElement,
      href: string,
      flash: string,
      callback: (view: View, joinCount: number) => void
    ): View;
    /** @private */
    joinRootViews(): boolean;
    /** @private */
    log(view: View, kind: string, msgCallback: () => [any, any]): void;
    /** @private */
    on(event: string, callback: (e: Event) => void): void;
    /** @private */
    onChannel(channel: Channel, event: string, cb: (data: any) => void): void;
    /** @private */
    owner(childEl: HTMLElement, callback: (view: View) => void): void;
    /** @private */
    pushHistoryPatch(href: string, linkState: any, targetEl: HTMLElement): void;
    /** @private */
    redirect(to: string, flash: string): void;
    /** @private */
    registerNewLocation(newLocation: Location): boolean;
    /** @private */
    reloadWithJitter(view: View): void;
    /** @private */
    replaceMain(
      href: string,
      flash: string,
      callback?: any,
      linkRef?: number
    ): void;
    /** @private */
    replaceRootHistory(): void;
    /** @private */
    restorePreviouslyActiveFocus(): void;
    /** @private */
    setActiveElement(target: Element): void;
    /** @private */
    setPendingLink(href: string): number;
    /** @private */
    silenceEvents(callback: () => void): void;
    /** @private */
    time(name: string, func: () => any): any;
    /** @private */
    triggerDOM(kind: string, args: any): void;
    /** @private */
    withinOwners(
      childEl: HTMLElement,
      callback: (view: View, el: HTMLElement) => void
    ): void;
    /** @private */
    withPageLoading(info: Event, callback: any): any;
    /** @private */
    wrapPush(view: View, opts: any, push: () => any): any;
  }

  interface View {
    isDead: boolean;
    liveSocket: LiveSocket;
    parent: View | undefined | null;
    root: View;
    el: HTMLElement;
    id: string;
    channel: Channel;
    getHook(el: HTMLElement): ViewHook | undefined;
    execNewMounted(): void;
    maybeAddNewHook(el: HTMLElement): void;
    maybeMounted(el: HTMLElement): void;
    afterElementsRemoved(els: HTMLElement[], pruneCids: boolean);
    triggerBeforeUpdateHook(
      fromEl: HTMLElement,
      toEl: HTMLElement
    ): ViewHook | undefined;
  }

  interface ViewHook<T extends object = {}> {
    __mounted: () => void;
    __beforeUpdate: () => void;
    __updated: () => void;
    __beforeDestroy: () => void;
    __destroyed: () => void;
    __disconnected: () => void;
    __reconnected: () => void;
  }

  interface ViewHookConstructor<T extends object> {
    new (view: View, el: HTMLElement, callbacks: any): ViewHook;
    makeID(): number;
    elementID(el: HTMLElement): number;
  }

  interface ViewHook<T extends object = {}> extends ViewHookConstructor<T> {
    constructor: ViewHookConstructor<T>;
  }

  interface ViewHookInternal {
    liveSocket: LiveSocket;
    /**  @private */
    __view: View;
  }

  interface Rendered {
    /** @private */
    comprehensionToBuffer(rendered: any, output: any): void;
    /** @private */
    createSpan(text: string, cid: number): HTMLSpanElement;
    /** @private */
    dynamicToBuffer(rendered: any, output: any): void;
    /** @private */
    get(): any;
    /** @private */
    isNewFingerprint(diff: object): boolean;
    /** @private */
    recursiveCIDToString(
      components: any,
      cid: string,
      onlyCids?: number[]
    ): any;
    /** @private */
    toOutputBuffer(rendered: any, output: object): any;
  }
}
