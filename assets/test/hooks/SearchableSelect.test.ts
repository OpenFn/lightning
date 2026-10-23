import { beforeEach, describe, expect, it } from 'vitest';

import { SearchableSelect } from '#/hooks/SearchableSelect';

const OPTIONS = ['Select a repository', 'openfn/lightning', 'openfn/kit'];

function setup() {
  document.body.innerHTML = `
    <div id="repo-searchable">
      <button type="button">toggle</button>
      <ul role="listbox">
        <li role="presentation"><input data-select-search type="text" /></li>
        ${OPTIONS.map(o => `<li role="option">${o}</li>`).join('')}
      </ul>
    </div>
  `;

  const el = document.getElementById('repo-searchable') as HTMLElement;
  const search = el.querySelector<HTMLInputElement>('input')!;
  const hook = Object.assign(Object.create(SearchableSelect), { el });
  hook.mounted();

  const options = () =>
    Array.from(el.querySelectorAll<HTMLElement>('li[role=option]'));
  const visible = () =>
    options()
      .filter(o => !o.hidden)
      .map(o => o.textContent);
  const type = (value: string) => {
    search.value = value;
    search.dispatchEvent(new Event('input'));
  };

  return { el, search, hook, options, visible, type };
}

const nextFrame = () => new Promise(resolve => requestAnimationFrame(resolve));

describe('SearchableSelect', () => {
  beforeEach(() => {
    document.body.innerHTML = '';
  });

  it('shows every option before anything is typed', () => {
    const { visible } = setup();

    expect(visible()).toEqual(OPTIONS);
  });

  it('hides options that do not match, ignoring case', () => {
    const { visible, type } = setup();

    type('LIGHT');

    expect(visible()).toEqual(['openfn/lightning']);
  });

  it('shows everything again when the filter is cleared', () => {
    const { visible, type } = setup();

    type('kit');
    type('');

    expect(visible()).toEqual(OPTIONS);
  });

  it('never hides the search row itself', () => {
    const { el, type } = setup();

    type('nothing matches this');

    expect(el.querySelector<HTMLElement>('li[role=presentation]')!.hidden).toBe(
      false
    );
  });

  it('reapplies the filter after a LiveView patch', () => {
    const { el, hook, visible, type } = setup();

    type('kit');

    // a patch re-renders the list with a new option and no hidden flags
    const added = document.createElement('li');
    added.setAttribute('role', 'option');
    added.textContent = 'openfn/kitchen';
    el.querySelector('ul')!.appendChild(added);
    el.querySelectorAll<HTMLElement>('li[role=option]').forEach(
      o => (o.hidden = false)
    );

    hook.updated();

    expect(visible()).toEqual(['openfn/kit', 'openfn/kitchen']);
  });

  it('clicks the first visible option on Enter without submitting', () => {
    const { search, options, type } = setup();
    const clicked: (string | null)[] = [];
    options().forEach(o =>
      o.addEventListener('click', () => clicked.push(o.textContent))
    );

    type('kit');
    const event = new KeyboardEvent('keydown', {
      key: 'Enter',
      cancelable: true,
    });
    search.dispatchEvent(event);

    expect(event.defaultPrevented).toBe(true);
    expect(clicked).toEqual(['openfn/kit']);
  });

  it('clears the filter and focuses the box when the list is opened', async () => {
    const { el, search, visible, type } = setup();

    type('kit');
    el.querySelector('button')!.click();
    await nextFrame();

    expect(search.value).toBe('');
    expect(visible()).toEqual(OPTIONS);
    expect(document.activeElement).toBe(search);
  });
});
