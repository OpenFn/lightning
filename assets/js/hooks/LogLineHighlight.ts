import { PhoenixHook } from './PhoenixHook';

const LogLineHighlight = {
  mounted() {
    this.highlightRows();
  },
  updated() {
    this.highlightRows();
  },
  highlightRows() {
    const highlightId = this.el.dataset['highlightId'];
    this.el.querySelectorAll('[data-highlight-id]').forEach(el => {
      let elementHighlightId = (el as HTMLElement).dataset['highlightId'];

      if (elementHighlightId === highlightId) {
        el.setAttribute('data-highlight', '');
      } else {
        el.removeAttribute('data-highlight');
      }
    });
  },
} as PhoenixHook<{ highlightRows: () => void }, { highlightId: null | string }>;

export default LogLineHighlight;
