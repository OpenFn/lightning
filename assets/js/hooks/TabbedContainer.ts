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

// When hash is null
// and the local storage is null
// Set the default tab to active

// When hash is null
// and the local storage is not null
// Set the tab from local storage to active

// When the hash is not null
// and the hash can be found in the tabs
// Set the tab from the hash to active

// When a tab is set it also sets local storage

function storeComponentHash(component: HTMLElement, hash: string | null) {
  if (hash) {
    localStorage.setItem(`${component.id}-hash`, hash);
  } else {
    localStorage.removeItem(`${component.id}-hash`);
  }
}

function getComponentHash(component: HTMLElement) {
  return localStorage.getItem(`${component.id}-hash`);
}

const TabbedSelector: PhoenixHook<{
  defaultHash: string | null;
  _onHashChange(e: Event): void;
  updateTabs(): void;
  findTarget(hash: string | null): HTMLElement | null;
  syncSelectedTab(): void;
}> = {
  mounted(this: typeof TabbedSelector) {
    console.debug('TabbedSelector', this.el);

    this.defaultHash = this.el.dataset.defaultHash || null;

    // Trigger a URL hash change when the server sends a 'push-hash' event.
    this.handleEvent<{ hash: string }>('push-hash', ({ hash }) => {
      window.location.hash = hash;
    });

    this._onHashChange = _evt => {
      this.syncSelectedTab();
      this.updateTabs();
    };

    window.addEventListener('hashchange', this._onHashChange);

    this.syncSelectedTab();
    this.updateTabs();
    const tabToSelect = getComponentHash(this.el);
    console.debug('tabToSelect', tabToSelect);
  },
  syncSelectedTab() {
    syncHash(this);
  },
  updated() {
    this.syncSelectedTab();
    this.updateTabs();
  },
  updateTabs() {
    const hashToSelect = getComponentHash(this.el);
    const targetTab = this.findTarget(hashToSelect);
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
  findTarget(hash: string | null) {
    if (!hash) {
      return null;
    }

    return this.el.querySelector<HTMLElement>(
      `[aria-controls="${hash}-panel"]`
    );
  },
  destroyed() {
    window.removeEventListener('hashchange', this._onHashChange);
  },
} as typeof TabbedSelector;

const TabbedPanels: PhoenixHook<{
  defaultHash: string | null;
  syncSelectedPanel(): void;
  findTarget(hash: string | null): HTMLElement | null;
  updatePanels(): void;
  _onHashChange(e: Event): void;
}> = {
  mounted(this: typeof TabbedPanels) {
    console.debug('TabbedPanels', this.el);
    this.defaultHash = this.el.dataset.defaultHash || null;

    // Trigger a URL hash change when the server sends a 'push-hash' event.
    this.handleEvent<{ hash: string }>('push-hash', ({ hash }) => {
      window.location.hash = hash;
    });

    this._onHashChange = _evt => {
      this.syncSelectedPanel();
      this.updatePanels();
    };

    window.addEventListener('hashchange', this._onHashChange);

    this.syncSelectedPanel();
    this.updatePanels();
  },
  updated() {
    this.syncSelectedPanel();
    this.updatePanels();
  },
  syncSelectedPanel() {
    syncHash(this);
  },
  updatePanels() {
    const hashToSelect = getComponentHash(this.el);
    const targetPanel = this.findTarget(hashToSelect);
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
  findTarget(hash: string | null) {
    if (!hash) {
      return null;
    }

    return this.el.querySelector<HTMLElement>(
      `[aria-labelledby="${hash}-tab"]`
    );
  },
  destroyed() {
    window.removeEventListener('hashchange', this._onHashChange);
  },
} as typeof TabbedPanels;

function syncHash(component: typeof TabbedSelector | typeof TabbedPanels) {
  const hash = getHash();

  // could be a tab that we don't have
  if (hash && component.findTarget(hash)) {
    storeComponentHash(component.el, hash);
  } else {
    const storedHash = getComponentHash(component.el);
    // if there is a stored hash, check if it exists in the tabs
    // if it doesn't exist, set the default hash
    if (!storedHash || !component.findTarget(storedHash)) {
      storeComponentHash(component.el, component.defaultHash);
    }
  }
}

export { TabbedContainer, TabbedSelector, TabbedPanels };
