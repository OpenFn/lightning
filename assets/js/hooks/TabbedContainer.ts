import type { PhoenixHook } from './PhoenixHook';

type TabbedContainer = PhoenixHook<{
  defaultHash: string | null;
  activeClasses: string[];
  disabledClasses: string[];
  inactiveClasses: string[];
  _onHashChange(e: Event): void;
  selectTab(hash: string | null): void;
}>;

const TabbedContainer = {
  mounted() {
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

export { TabbedContainer };
