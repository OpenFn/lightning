/**
 * Tests for the LocalDateTimeInput hook.
 *
 * The hook pairs a `datetime-local` picker (browser timezone) with the hidden
 * input the form submits (UTC). See
 * https://github.com/OpenFn/lightning/issues/4983.
 */

import {
  afterAll,
  beforeAll,
  beforeEach,
  describe,
  expect,
  test,
} from 'vitest';

import { LocalDateTimeInput } from '../../js/hooks';

const originalTZ = process.env['TZ'];

interface Harness {
  hook: { mounted: () => void; updated: () => void };
  form: HTMLFormElement;
  hidden: HTMLInputElement;
  picker: HTMLInputElement;
  formEvents: Event[];
}

function mountHook(value?: string): Harness {
  document.body.innerHTML = `
    <form>
      <div id="filter-container" data-hidden-el="filter" data-local-el="filter_local">
        <input type="hidden" name="filters[date_after]" id="filter" ${
          value === undefined ? '' : `value="${value}"`
        } />
        <input type="datetime-local" id="filter_local" />
      </div>
    </form>
  `;

  const form = document.querySelector('form') as HTMLFormElement;
  const formEvents: Event[] = [];
  form.addEventListener('input', event => formEvents.push(event));

  const hook = Object.create(LocalDateTimeInput) as Harness['hook'] & {
    el: HTMLElement;
  };
  hook.el = document.getElementById('filter-container') as HTMLElement;
  hook.mounted();

  return {
    hook,
    form,
    hidden: document.getElementById('filter') as HTMLInputElement,
    picker: document.getElementById('filter_local') as HTMLInputElement,
    formEvents,
  };
}

describe('LocalDateTimeInput in a UTC+1 timezone', () => {
  beforeAll(() => {
    process.env['TZ'] = 'Europe/Berlin';
  });

  afterAll(() => {
    process.env['TZ'] = originalTZ;
  });

  beforeEach(() => {
    document.body.innerHTML = '';
  });

  test('shows the submitted UTC value as local time', () => {
    const { picker } = mountHook('2026-01-17T15:40:00Z');

    expect(picker.value).toBe('2026-01-17T16:40');
  });

  test('leaves the picker empty when no filter is set', () => {
    const { picker } = mountHook();

    expect(picker.value).toBe('');
  });

  test('submits the picked local time as UTC', () => {
    const { hidden, picker, formEvents } = mountHook();

    picker.value = '2026-01-17T16:40';
    picker.dispatchEvent(new Event('change', { bubbles: true }));

    expect(hidden.value).toBe('2026-01-17T15:40:00.000Z');

    // Exactly one event reaches the form, and it comes from the input that
    // carries the name - so phx-change sees the UTC value, never the picker's
    // wall clock.
    expect(formEvents.map(event => event.target)).toEqual([hidden]);
  });

  test('clears the hidden value when the picker is emptied', () => {
    const { hidden, picker } = mountHook('2026-01-17T15:40:00Z');

    picker.value = '';
    picker.dispatchEvent(new Event('change', { bubbles: true }));

    expect(hidden.value).toBe('');
  });

  test('keeps a half-entered date off the form', () => {
    const { picker, formEvents } = mountHook();

    picker.dispatchEvent(new Event('input', { bubbles: true }));

    expect(formEvents).toEqual([]);
  });

  test('follows the value the server re-renders', () => {
    const { hook, hidden, picker } = mountHook('2026-01-17T15:40:00Z');

    // What clearing the filter server-side leaves behind: the property is
    // whatever the hook last wrote, only the attribute is patched.
    hidden.removeAttribute('value');
    hook.updated();

    expect(picker.value).toBe('');
    expect(hidden.value).toBe('');
  });

  test('leaves a picker the user is working in alone', () => {
    const { hook, hidden, picker } = mountHook('2026-01-17T15:40:00Z');

    picker.focus();
    picker.value = '2026-01-17T18:00';
    hidden.setAttribute('value', '2026-01-17T15:40:00Z');
    hook.updated();

    expect(picker.value).toBe('2026-01-17T18:00');
  });
});
