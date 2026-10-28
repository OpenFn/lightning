import type { PhoenixHook } from './PhoenixHook';

type HashPanel = PhoenixHook<
  { _onHashChange: () => void; show(): void },
  { hash: string; defaultHash: string }
>;

/**
 * Shows its element only while the URL hash is `data-hash` (or there is no
 * hash and `data-default-hash` is the same). For HEEx drawn beside a
 * design-system page whose tabs are the hash.
 */
const HashPanel = {
  mounted() {
    this._onHashChange = () => this.show();
    window.addEventListener('hashchange', this._onHashChange);
    this.show();
  },
  updated() {
    this.show();
  },
  show() {
    const hash =
      window.location.hash.replace('#', '') || this.el.dataset.defaultHash;
    this.el.classList.toggle('hidden', hash !== this.el.dataset.hash);
  },
  destroyed() {
    window.removeEventListener('hashchange', this._onHashChange);
  },
} as HashPanel;

export { HashPanel };
