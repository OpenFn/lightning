import { PhoenixHook } from './PhoenixHook';

type TabbedContainer = PhoenixHook<{
  defaultHash: string | null;
  activeClasses: string[];
  disabledClasses: string[];
  inactiveClasses: string[];
  _onHashChange(e: Event): void;
  selectTab(hash: string | null): void;
}>;

function getHash() {
  return window.location.hash.replace('#', '') || null;
}

function getHashFromTab(tab: HTMLElement) {
  return tab.getAttribute('aria-controls')?.replace('-panel', '') || null;
}

const TabbedContainer = {
  mounted(this: TabbedContainer) {
    this.defaultHash = this.el.dataset.defaultHash || null;

    // Trigger a URL hash change when the server sends a 'push-hash' event.
    this.handleEvent<{ hash: string }>('push-hash', ({ hash }) => {
      window.location.hash = hash;
    });

    this._onHashChange = _evt => {
      this.selectTab(getHash());
    };

    window.addEventListener('hashchange', this._onHashChange);

    this.selectTab(getHash() || this.defaultHash);
  },
  updated() {
    this.selectTab(getHash());
  },
  selectTab(nextHash: string | null) {
    if (!nextHash) {
      return;
    }

    const targetTab: HTMLElement | null = this.el.querySelector<HTMLElement>(
      `[aria-controls="${nextHash}-panel"]`
    );

    if (!targetTab) {
      return;
    }

    requestAnimationFrame(() => {
      const parent = targetTab.parentNode!;
      parent
        .querySelectorAll<HTMLElement>('[aria-selected="true"]')
        .forEach(tab => {
          tab.setAttribute('aria-selected', 'false');
        });

      targetTab.setAttribute('aria-selected', 'true');

      this.el
        .querySelectorAll<HTMLElement>('[role=tabpanel]')
        .forEach(panel => {
          panel.classList.add('hidden');
        });

      this.el
        .querySelector(`#${targetTab.getAttribute('aria-controls')}`)
        ?.classList.remove('hidden');
    });
  },
  destroyed() {
    window.removeEventListener('hashchange', this._onHashChange);
  },
} as TabbedContainer;

const TabbedSelector: PhoenixHook<{
  defaultHash: string | null;
  selectTab(nextHash: string | null): void;
  _onHashChange(e: Event): void;
}> = {
  mounted(this: typeof TabbedSelector) {
    this.defaultHash = this.el.dataset.defaultHash || null;

    // Trigger a URL hash change when the server sends a 'push-hash' event.
    this.handleEvent<{ hash: string }>('push-hash', ({ hash }) => {
      window.location.hash = hash;
    });

    this._onHashChange = _evt => {
      this.selectTab(getHash());
    };

    window.addEventListener('hashchange', this._onHashChange);

    this.selectTab(getHash() || this.defaultHash);
  },
  updated() {
    const selected = this.el.querySelector<HTMLElement>(
      '[aria-selected="true"]'
    );

    // If there is a currently selected tab, and the URL hash is not set,
    // set the URL hash to the selected tab.
    // This is useful when the user navigates to a page with a selected tab
    // but the hash url is not set (the server isn't aware of hash state).
    if (selected) {
      let selectedTabHash = getHashFromTab(selected);

      if (selectedTabHash && getHash() === null) {
        window.location.hash = selectedTabHash;
      }
    } else {
      this.selectTab(getHash() || this.defaultHash);
    }
  },
  selectTab(nextHash: string | null) {
    if (!nextHash) {
      return;
    }

    const targetTab: HTMLElement | null = this.el.querySelector<HTMLElement>(
      `[aria-controls="${nextHash}-panel"]`
    );

    if (!targetTab) {
      return;
    }

    requestAnimationFrame(() => {
      const parent = targetTab.parentNode!;
      parent
        .querySelectorAll<HTMLElement>('[aria-selected="true"]')
        .forEach(tab => {
          tab.setAttribute('aria-selected', 'false');
        });

      targetTab.setAttribute('aria-selected', 'true');
    });
  },
  destroyed() {
    window.removeEventListener('hashchange', this._onHashChange);
  },
} as typeof TabbedSelector;

const TabbedPanels: PhoenixHook<{
  defaultHash: string | null;
  showPanel(nextHash: string | null): void;
  _onHashChange(e: Event): void;
}> = {
  mounted(this: typeof TabbedPanels) {
    this.defaultHash = this.el.dataset.defaultHash || null;

    // Trigger a URL hash change when the server sends a 'push-hash' event.
    this.handleEvent<{ hash: string }>('push-hash', ({ hash }) => {
      window.location.hash = hash;
    });

    this._onHashChange = _evt => {
      this.showPanel(getHash() || this.defaultHash);
    };

    window.addEventListener('hashchange', this._onHashChange);

    this.showPanel(getHash() || this.defaultHash);
  },
  updated() {
    this.showPanel(getHash() || this.defaultHash);
  },
  showPanel(nextHash: string | null) {
    if (!nextHash) {
      return;
    }

    const targetPanel: HTMLElement | null = this.el.querySelector<HTMLElement>(
      `[aria-labelledby="${nextHash}-tab"]`
    );

    if (!targetPanel) {
      return;
    }

    requestAnimationFrame(() => {
      this.el
        .querySelectorAll<HTMLElement>('[role=tabpanel]')
        .forEach(panel => {
          panel.classList.add('hidden');
        });

      targetPanel.classList.remove('hidden');
    });
  },
  destroyed() {
    window.removeEventListener('hashchange', this._onHashChange);
  },
} as typeof TabbedPanels;

export { TabbedContainer, TabbedSelector, TabbedPanels };
