import { PhoenixHook } from './PhoenixHook';

type TabSelector = PhoenixHook<{
  contentItems: NodeListOf<HTMLElement>;
  defaultHash: string;
  activeClasses: string[];
  disabledClasses: string[];
  inactiveClasses: string[];
  _onHashChange(e: Event): void;
  hashChanged(hash: string): void;
  getHash(): string;
  applyStyles(activeTab: HTMLElement | null, inactiveTabs: HTMLElement[]): void;
}>;

export default {
  mounted(this: TabSelector) {
    this.contentItems = document.querySelectorAll('[data-panel-hash]');

    const { activeClasses, inactiveClasses, defaultHash, disabledClasses } =
      this.el.dataset;
    if (
      !activeClasses ||
      !inactiveClasses ||
      !defaultHash ||
      !disabledClasses
    ) {
      throw new Error(
        'TabSelector tab_bar component missing data-active-classes, data-inactive-classes or data-default-hash.'
      );
    }

    // Trigger a URL hash change when the server sends a 'push-hash' event.
    this.handleEvent<{ hash: string }>('push-hash', ({ hash }) => {
      window.location.hash = hash;
    });

    this._onHashChange = _evt => {
      const hash = window.location.hash.replace('#', '');
      this.hashChanged(hash);
    };

    this.activeClasses = activeClasses.split(' ');
    this.inactiveClasses = inactiveClasses.split(' ');
    this.disabledClasses = disabledClasses?.split(' ');
    this.defaultHash = defaultHash;

    window.addEventListener('hashchange', this._onHashChange);

    console.log({ getHash: this.getHash(), defaultHash: this.defaultHash });

    this.hashChanged(this.getHash() || this.defaultHash);
  },
  hashChanged(nextHash: string) {
    let activePanel: HTMLElement | null = null;
    let inactivePanels: HTMLElement[] = [];

    this.el.querySelectorAll<HTMLElement>('[id^=tab-item]').forEach(elem => {
      const { hash } = elem.dataset;
      const panel = document.querySelector(
        `[data-panel-hash=${hash}]`
      ) as HTMLElement;

      if (!panel) {
        console.error(
          `TabSelector tab_bar component missing data-panel-hash=${hash}`
        );
      } else {
        if (nextHash == hash) {
          if (panel.style.display == 'none') {
            panel.style.display = 'block';
          }

          activePanel = elem;
        } else {
          inactivePanels.push(elem);
        }
      }
    });

    this.applyStyles(activePanel, inactivePanels);
  },
  destroyed() {
    window.removeEventListener('hashchange', this._onHashChange);
  },
  getHash() {
    return window.location.hash.replace('#', '');
  },
  applyStyles(activeTab: HTMLElement | null, inactiveTabs: HTMLElement[]) {
    inactiveTabs.forEach(elem => {
      console.log(elem.dataset);
      if (elem.hasAttribute('data-disabled')) {
        console.log(elem);

        elem.classList.remove(...this.activeClasses);
        elem.classList.remove(...this.inactiveClasses);
        elem.classList.add(...this.disabledClasses);
        return;
      }

      elem.classList.remove(...this.activeClasses);
      elem.classList.add(...this.inactiveClasses);
    });

    if (activeTab) {
      activeTab.classList.remove(...this.inactiveClasses);
      activeTab.classList.add(...this.activeClasses);
    }
  },
} as TabSelector;
