import { PhoenixHook } from './PhoenixHook';

type TabbedContainer = PhoenixHook<{
  defaultHash: string | null;
  activeClasses: string[];
  disabledClasses: string[];
  inactiveClasses: string[];
  _onHashChange(e: Event): void;
  selectTab(hash: string | null): void;
}>;

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

function getHash() {
  return window.location.hash.replace('#', '') || null;
}

function storageKey(component: HTMLElement) {
  return component.dataset.storageKey || `${component.id}-hash`;
}

function storeComponentHash(component: HTMLElement, hash: string | null) {
  const key = storageKey(component);
  if (hash) {
    localStorage.setItem(key, hash);
  } else {
    localStorage.removeItem(key);
  }
}

function getComponentHash(component: HTMLElement) {
  const key = storageKey(component);
  return localStorage.getItem(key);
}

const TabbedSelector: PhoenixHook<{
  defaultHash: string | null;
  _onHashChange(e: Event): void;
  updateTabs(): void;
  findTarget(hash: string | null): HTMLElement | null;
  syncSelectedTab(): void;
}> = {
  mounted(this: typeof TabbedSelector) {
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
    window.addEventListener('phx:page-loading-stop', this._onHashChange);

    this.syncSelectedTab();
    this.updateTabs();
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
    if (!targetTab) return;

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
    if (!hash) return null;

    return this.el.querySelector<HTMLElement>(
      `[aria-controls="${hash}-panel"]`
    );
  },
  destroyed() {
    window.removeEventListener('hashchange', this._onHashChange);
    window.removeEventListener('phx:page-loading-stop', this._onHashChange);
  },
} as typeof TabbedSelector;

const TabbedPanels: PhoenixHook<{
  defaultHash: string | null;
  _onHashChange(e: Event): void;
  updatePanels(): void;
  findTarget(hash: string | null): HTMLElement | null;
  syncSelectedPanel(): void;
}> = {
  mounted(this: typeof TabbedPanels) {
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
    window.addEventListener('phx:page-loading-stop', this._onHashChange);

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
    if (!hash) return null;

    return this.el.querySelector<HTMLElement>(
      `[aria-labelledby="${hash}-tab"]`
    );
  },
  destroyed() {
    window.removeEventListener('hashchange', this._onHashChange);
    window.removeEventListener('phx:page-loading-stop', this._onHashChange);
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
