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
          panel.setAttribute('hidden', 'true');
        });

      this.el
        .querySelector(`#${targetTab.getAttribute('aria-controls')}`)
        ?.removeAttribute('hidden');
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
  selectTab(nextHash: string | null) {
    console.debug('TabbedSelector: selectTab', nextHash);
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
      console.log('push-hash', [hash, window.location.hash]);

      window.location.hash = hash;
    });

    this._onHashChange = _evt => {
      this.showPanel(getHash());
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
          panel.setAttribute('hidden', 'true');
        });

      targetPanel.removeAttribute('hidden');
    });
  },
  destroyed() {
    window.removeEventListener('hashchange', this._onHashChange);
  },
} as typeof TabbedPanels;

export { TabbedContainer, TabbedSelector, TabbedPanels };
