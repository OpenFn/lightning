import { act, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { Picker, type PickerItem } from '#/picker/Picker';

const defaults = {
  'data-placeholder': 'Search projects...',
  'data-empty-message': 'No projects found',
  'data-view-all-label': 'View all projects',
  'data-view-all-href': '/projects',
  'data-open-event': 'open-project-picker',
};

function mountPicker(items: PickerItem[], currentId?: string) {
  return render(
    <Picker
      {...defaults}
      data-items={JSON.stringify(items)}
      {...(currentId ? { 'data-current-id': currentId } : {})}
    />
  );
}

function openPicker(eventName = 'open-project-picker') {
  act(() => {
    document.body.dispatchEvent(new CustomEvent(eventName));
  });
}

function closePicker() {
  act(() => {
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
  });
}

function listedLabels(): string[] {
  // First option is "View all"; everything after is a real item.
  return screen
    .queryAllByRole('option')
    .slice(1)
    .map(el => el.textContent?.trim() ?? '');
}

function item(
  id: string,
  label: string,
  depth: number,
  overrides: Partial<PickerItem> = {}
): PickerItem {
  return {
    id,
    label,
    searchLabel:
      overrides.searchLabel ?? (depth === 0 ? label : `parent/${label}`),
    depth,
    href: overrides.href ?? `/projects/${id}/w`,
    ...(overrides.color !== undefined ? { color: overrides.color } : {}),
  };
}

describe('Picker content rendering', () => {
  afterEach(closePicker);

  test('renders items in the order the server sent them', () => {
    mountPicker([
      item('1', 'alpha', 0),
      item('2', 'beta', 0),
      item('3', 'gamma', 0),
    ]);
    openPicker();
    expect(listedLabels()).toEqual(['alpha', 'beta', 'gamma']);
  });

  test('uses the configured view-all label and placeholder', () => {
    mountPicker([item('1', 'alpha', 0)]);
    openPicker();

    expect(
      screen.getByPlaceholderText('Search projects...')
    ).toBeInTheDocument();
    expect(screen.getByText('View all projects')).toBeInTheDocument();
  });

  test('shows the configured empty message when items is empty', () => {
    mountPicker([]);
    openPicker();
    expect(screen.getByText('No projects found')).toBeInTheDocument();
  });

  test('respects depth for indentation via paddingLeft', () => {
    mountPicker([
      item('1', 'root', 0),
      item('2', 'child', 1),
      item('3', 'grandchild', 2),
    ]);
    openPicker();

    const options = screen.getAllByRole('option').slice(1);
    expect((options[0] as HTMLElement).style.paddingLeft).toBe('16px');
    expect((options[1] as HTMLElement).style.paddingLeft).toBe('26px');
    expect((options[2] as HTMLElement).style.paddingLeft).toBe('36px');
  });
});

describe('Picker search', () => {
  let user: ReturnType<typeof userEvent.setup>;

  beforeEach(() => {
    user = userEvent.setup();
  });

  afterEach(closePicker);

  test('filters by searchLabel (case-insensitive)', async () => {
    mountPicker([
      item('1', 'ethiopia', 0, { searchLabel: 'ethiopia' }),
      item('2', 'kenya', 0, { searchLabel: 'kenya' }),
      item('3', 'rwanda', 0, { searchLabel: 'rwanda' }),
    ]);
    openPicker();

    await user.type(screen.getByRole('combobox'), 'KEN');
    expect(listedLabels()).toEqual(['kenya']);
  });

  test('keeps ancestors visible when a descendant matches', async () => {
    mountPicker([
      item('r', 'ethiopia', 0, { searchLabel: 'ethiopia' }),
      item('a', 'feb-red-team', 1, { searchLabel: 'ethiopia/feb-red-team' }),
      item('b', 'nov-blue-team', 1, { searchLabel: 'ethiopia/nov-blue-team' }),
    ]);
    openPicker();

    await user.type(screen.getByRole('combobox'), 'red');
    const labels = listedLabels();
    expect(labels).toContain('ethiopia');
    expect(labels).toContain('feb-red-team');
    expect(labels).not.toContain('nov-blue-team');
  });

  test('empty search shows everything', async () => {
    mountPicker([
      item('1', 'a', 0, { searchLabel: 'a' }),
      item('2', 'b', 0, { searchLabel: 'b' }),
    ]);
    openPicker();

    const input = screen.getByRole('combobox');
    await user.type(input, 'x');
    await user.clear(input);

    expect(listedLabels()).toEqual(['a', 'b']);
  });

  test('no matches shows the empty message', async () => {
    mountPicker([item('1', 'alpha', 0, { searchLabel: 'alpha' })]);
    openPicker();
    await user.type(screen.getByRole('combobox'), 'zzz');
    expect(screen.getByText('No projects found')).toBeInTheDocument();
  });
});

describe('Picker navigation', () => {
  let hrefSetter: ReturnType<typeof vi.fn>;
  let originalLocation: Location;

  beforeEach(() => {
    hrefSetter = vi.fn();
    originalLocation = window.location;
    delete (window as unknown as { location?: Location }).location;
    (window as unknown as { location: unknown }).location = {
      pathname: '/',
      search: '',
      hash: '',
      get href() {
        return '';
      },
      set href(value: string) {
        hrefSetter(value);
      },
    };
  });

  afterEach(() => {
    (window as unknown as { location: Location }).location = originalLocation;
    closePicker();
  });

  test('navigates to the server-provided href on click', () => {
    mountPicker([item('target', 'target', 0, { href: '/projects/target/w' })]);
    openPicker();

    const targetOption = screen
      .getAllByRole('option')
      .find(o => within(o).queryByText('target'))!;
    act(() => {
      targetOption.click();
    });

    expect(hrefSetter).toHaveBeenCalledWith('/projects/target/w');
  });

  test('uses data-view-all-href for the view-all row', () => {
    render(
      <Picker
        {...defaults}
        data-items={JSON.stringify([])}
        data-view-all-href="/somewhere"
      />
    );
    openPicker();

    const viewAll = screen
      .getAllByRole('option')
      .find(o => within(o).queryByText('View all projects'))!;
    act(() => {
      viewAll.click();
    });

    expect(hrefSetter).toHaveBeenCalledWith('/somewhere');
  });
});

describe('Picker open event', () => {
  afterEach(closePicker);

  test('opens on the configured event', () => {
    render(
      <Picker
        {...defaults}
        data-items={JSON.stringify([item('1', 'alpha', 0)])}
        data-open-event="open-custom-picker"
      />
    );
    openPicker('open-custom-picker');
    expect(screen.getByRole('combobox')).toBeInTheDocument();
  });

  test('does not open on a different event', () => {
    render(
      <Picker
        {...defaults}
        data-items={JSON.stringify([item('1', 'alpha', 0)])}
        data-open-event="open-custom-picker"
      />
    );
    openPicker('some-other-event');
    expect(screen.queryByRole('combobox')).not.toBeInTheDocument();
  });
});

describe('Picker current selection', () => {
  afterEach(closePicker);

  test('marks the current item as selected via aria', () => {
    mountPicker([item('1', 'alpha', 0), item('2', 'beta', 0)], '2');
    openPicker();

    const options = screen.getAllByRole('option');
    const beta = options.find(o => within(o).queryByText('beta'));
    expect(beta).toHaveAttribute('aria-selected', 'true');
  });
});
