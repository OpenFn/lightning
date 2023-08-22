import tippy, { Instance as TippyInstance } from 'tippy.js';
import { PhoenixHook } from './PhoenixHook';

export const Flash = {
  mounted() {
    let hide = () =>
      this.liveSocket.execJS(this.el, this.el.getAttribute('phx-click'));
    this.timer = setTimeout(() => hide(), 5000);
    this.el.addEventListener('phx:hide-start', () => clearTimeout(this.timer));
    this.el.addEventListener('mouseover', () => {
      clearTimeout(this.timer);
      this.timer = setTimeout(() => hide(), 5000);
    });
  },
  destroyed() {
    clearTimeout(this.timer);
  },
} as PhoenixHook<{ timer: ReturnType<typeof setTimeout> }>;

export const Tooltip = {
  mounted() {
    if (!this.el.ariaLabel) {
      console.warn('Tooltip element missing aria-label attribute', this.el);
      return;
    }

    let content = this.el.ariaLabel;
    this._tippyInstance = tippy(this.el, {
      content: content,
    });
  },
  destroyed() {
    if (this._tippyInstance) this._tippyInstance.unmount();
  },
} as PhoenixHook<{ _tippyInstance: TippyInstance | null }>;

export const AssocListChange = {
  mounted() {
    this.el.addEventListener('change', _event => {
      this.pushEventTo(this.el, 'select_item', { id: this.el.value });
    });
  },
} as PhoenixHook<{}, {}, HTMLSelectElement>;

export const SubmitViaCtrlS = {
  mounted() {
    this.callback = this.handleEvent.bind(this);
    window.addEventListener('keydown', this.callback);
  },
  handleEvent(e: KeyboardEvent) {
    if ((e.ctrlKey || e.metaKey) && e.key === 's') {
      e.preventDefault();
      this.el.dispatchEvent(
        new Event('submit', { bubbles: true, cancelable: true })
      );
    }
  },
  destroyed() {
    window.removeEventListener('keydown', this.callback);
  },
} as PhoenixHook<{
  callback: (e: KeyboardEvent) => void;
  handleEvent: (e: KeyboardEvent) => void;
}>;

export const FocusInput = {
  mounted() {
    this.el.addEventListener('click', e => {
      let input = this.el.closest('.relative').querySelector('input');
      if (input) {
        input.focus();
      }
    });
  },
};

export const Copy = {
  mounted() {
    let { to } = this.el.dataset;
    const phxThenAttribute = this.el.getAttribute('phx-then');
    this.el.addEventListener('click', ev => {
      ev.preventDefault();
      let text = document.querySelector(to).value;
      navigator.clipboard.writeText(text).then(() => {
        console.log('Copied!');
        if (phxThenAttribute !== null) {
          this.liveSocket.execJS(this.el, phxThenAttribute);
        }
      });
    });
  },
} as PhoenixHook<{}, { to: string }>;
