import type { PhoenixHook } from './PhoenixHook';

type SearchableSelect = PhoenixHook<{
  search: HTMLInputElement | null;
  applyFilter(): void;
  focusSearch(framesLeft?: number): void;
}>;

/**
 * Adds a text filter to the `custom-select` input (`searchable` attr).
 *
 * Options are filtered client-side by hiding non-matching `li[role=option]`
 * elements. The filter is re-applied after every LiveView patch so a re-render
 * of the options doesn't leave the list out of sync with the search box.
 */
const SearchableSelect = {
  mounted() {
    this.search = this.el.querySelector<HTMLInputElement>(
      'input[data-select-search]'
    );

    if (!this.search) return;

    this.search.addEventListener('input', () => this.applyFilter());

    this.search.addEventListener('keydown', e => {
      // Don't submit the surrounding form.
      if (e.key === 'Enter') {
        e.preventDefault();
        this.el
          .querySelector<HTMLElement>('li[role=option]:not([hidden])')
          ?.click();
      }
    });

    // The wrapper's phx-click opens the list; focus the search box and start
    // with a clean filter whenever the toggle button is clicked.
    this.el.querySelector('button')?.addEventListener('click', () => {
      if (!this.search) return;
      this.search.value = '';
      this.applyFilter();
      this.focusSearch();
    });
  },
  updated() {
    this.applyFilter();
  },
  // LiveView shows the list after this click handler runs, and a hidden input
  // can't take focus, so retry for a few frames until the focus sticks.
  focusSearch(framesLeft = 10) {
    requestAnimationFrame(() => {
      this.search?.focus();
      if (document.activeElement !== this.search && framesLeft > 0) {
        this.focusSearch(framesLeft - 1);
      }
    });
  },
  applyFilter() {
    const term = (this.search?.value ?? '').trim().toLowerCase();

    this.el.querySelectorAll<HTMLElement>('li[role=option]').forEach(option => {
      const label = (option.textContent ?? '').toLowerCase();
      option.hidden = term !== '' && !label.includes(term);
    });
  },
} as SearchableSelect;

export { SearchableSelect };
