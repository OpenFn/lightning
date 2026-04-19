import type { PhoenixHook } from './PhoenixHook';

type OtpInput = PhoenixHook<
  {
    boxes: HTMLInputElement[];
    lastSubmitted: string;
    _onInput(e: Event): void;
    _onKeyDown(e: KeyboardEvent): void;
    _onPaste(e: ClipboardEvent): void;
    _onFocus(e: FocusEvent): void;
    sync(): void;
    clear(): void;
  },
  {
    hiddenTarget?: string;
    autofocus?: string;
    validateEvent?: string;
    submitEvent?: string;
  }
>;

const OtpInput = {
  mounted() {
    this.boxes = Array.from(
      this.el.querySelectorAll<HTMLInputElement>('input[data-otp-box]')
    );
    this.lastSubmitted = '';

    this.handleEvent<{ id?: string }>('otp:clear', payload => {
      if (payload.id && payload.id !== this.el.id) return;
      this.clear();
    });

    this._onInput = (e: Event) => {
      const input = e.target as HTMLInputElement;
      const index = Number(input.dataset['index']);
      const value = input.value.replace(/\D/g, '').slice(0, 1);
      input.value = value;

      if (value && index < this.boxes.length - 1) {
        this.boxes[index + 1]?.focus();
      }

      this.sync();
    };

    this._onKeyDown = (e: KeyboardEvent) => {
      const input = e.target as HTMLInputElement;
      const index = Number(input.dataset['index']);

      if (e.key === 'Backspace' && !input.value && index > 0) {
        e.preventDefault();
        const prev = this.boxes[index - 1];
        if (prev) {
          prev.focus();
          prev.value = '';
          this.sync();
        }
      } else if (e.key === 'ArrowLeft' && index > 0) {
        e.preventDefault();
        this.boxes[index - 1]?.focus();
      } else if (e.key === 'ArrowRight' && index < this.boxes.length - 1) {
        e.preventDefault();
        this.boxes[index + 1]?.focus();
      }
    };

    this._onPaste = (e: ClipboardEvent) => {
      e.preventDefault();
      const text = e.clipboardData?.getData('text') ?? '';
      const digits = text.replace(/\D/g, '').slice(0, this.boxes.length);
      if (digits.length === 0) return;

      this.boxes.forEach((box, i) => {
        box.value = digits[i] ?? '';
      });

      const lastFilled = Math.min(digits.length, this.boxes.length) - 1;
      this.boxes[lastFilled]?.focus();
      this.sync();
    };

    this._onFocus = (e: FocusEvent) => {
      (e.target as HTMLInputElement).select();
    };

    this.boxes.forEach(box => {
      box.addEventListener('input', this._onInput);
      box.addEventListener('keydown', this._onKeyDown);
      box.addEventListener('paste', this._onPaste);
      box.addEventListener('focus', this._onFocus);
    });

    if (this.el.dataset.autofocus === 'true') {
      this.boxes[0]?.focus();
    }
  },
  sync() {
    const code = this.boxes.map(b => b.value).join('');

    const selector = this.el.dataset['hiddenTarget'];
    if (selector) {
      const hidden = document.querySelector<HTMLInputElement>(selector);
      if (hidden) hidden.value = code;
    }

    const validateEvent = this.el.dataset['validateEvent'];
    if (validateEvent) this.pushEventTo(this.el, validateEvent, { code });

    const submitEvent = this.el.dataset['submitEvent'];
    if (
      submitEvent &&
      code.length === this.boxes.length &&
      code !== this.lastSubmitted
    ) {
      this.lastSubmitted = code;
      this.pushEventTo(this.el, submitEvent, { code });
    }
  },
  clear() {
    this.boxes.forEach(b => {
      b.value = '';
    });
    this.lastSubmitted = '';
    this.boxes[0]?.focus();

    const selector = this.el.dataset['hiddenTarget'];
    if (selector) {
      const hidden = document.querySelector<HTMLInputElement>(selector);
      if (hidden) hidden.value = '';
    }
  },
  destroyed() {
    this.boxes.forEach(box => {
      box.removeEventListener('input', this._onInput);
      box.removeEventListener('keydown', this._onKeyDown);
      box.removeEventListener('paste', this._onPaste);
      box.removeEventListener('focus', this._onFocus);
    });
  },
} as OtpInput;

export { OtpInput };
