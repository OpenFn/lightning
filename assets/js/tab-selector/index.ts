interface TabSelector {
  el: HTMLElement;
  tabItems: NodeListOf<HTMLElement>;
  contentItems: NodeListOf<HTMLElement>;
  defaultHash: string;
  activeClasses: string[];
  inactiveClasses: string[];
  _onHashChange(e: Event): void;
  mounted(): void;
  destroyed(): void;
  hashChanged(hash: string): void;
  handleEvent(eventName: string, callback: (d: {}) => void): any;
}

export default {
  mounted(this: TabSelector) {
    console.log('TabSelector mounted');
    this.tabItems = this.el.querySelectorAll('[id^=tab-item]');
    this.contentItems = document.querySelectorAll('[data-panel-hash]');

    const { activeClasses, inactiveClasses, defaultHash } = this.el.dataset;
    if (!activeClasses || !inactiveClasses || !defaultHash) {
      throw new Error(
        'TabSelector tab_bar component missing data-active-classes, data-inactive-classes or data-default-hash.'
      );
    }

    // Trigger a URL hash change when the server sends a 'push-hash' event.
    this.handleEvent('push-hash', ({ hash }) => {
      window.location.hash = hash;
    });

    this._onHashChange = _evt => {
      const hash = window.location.hash.replace('#', '');
      this.hashChanged(hash);
    };

    this.activeClasses = activeClasses.split(' ');
    this.inactiveClasses = inactiveClasses.split(' ');
    this.defaultHash = defaultHash;

    window.addEventListener('hashchange', this._onHashChange);

    this.hashChanged(window.location.hash.replace('#', '') || this.defaultHash);
  },
  hashChanged(newHash: string) {
    this.tabItems.forEach(elem => {
      const { hash } = elem.dataset;
      const panel = document.querySelector(
        `[data-panel-hash=${hash}]`
      ) as HTMLElement;

      if (newHash == hash) {
        panel.style.display = 'block';

        elem.classList.remove(...this.inactiveClasses);
        elem.classList.add(...this.activeClasses);
      } else {
        panel.style.display = 'none';

        elem.classList.remove(...this.activeClasses);
        elem.classList.add(...this.inactiveClasses);
      }
    });
  },
  destroyed() {
    window.removeEventListener('hashchange', this._onHashChange);
  },
} as TabSelector;
