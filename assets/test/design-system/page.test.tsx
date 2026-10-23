import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import {
  designSystemPage,
  type PageActions,
} from '../../js/design-system/page';

import { renderIsland } from './renderIsland';

interface Props {
  rows: { id: string }[];
}

let seen: { props: Props; actions: PageActions }[] = [];

const Page = ({
  label,
  onGo,
}: {
  label: string;
  onGo: () => Promise<void>;
}) => <button onClick={() => void onGo()}>{label}</button>;

const Island = designSystemPage(
  'ThingsPage',
  Page,
  ['/things', '/things/:id'],
  (props: Props, actions) => {
    seen.push({ props, actions });
    return {
      label: `${props.rows.length} rows`,
      onGo: () => actions.send('go'),
    };
  }
);

const last = () => {
  const entry = seen[seen.length - 1];
  if (!entry) throw new Error('The island has not rendered');
  return entry;
};

describe('designSystemPage', () => {
  beforeEach(() => {
    seen = [];
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  test('parses data-props and keeps unchanged records by identity', () => {
    const { setProps } = renderIsland<Props>(Island, {
      rows: [{ id: 'a' }, { id: 'b' }],
    });
    const first = last().props;

    setProps({ rows: [{ id: 'a' }, { id: 'c' }] });

    expect(screen.getByRole('button')).toHaveTextContent('2 rows');
    expect(last().props).not.toBe(first);
    expect(last().props.rows[0]).toBe(first.rows[0]);
    expect(last().props.rows[1]).not.toBe(first.rows[1]);
  });

  test('send resolves on an empty reply and on null', async () => {
    renderIsland<Props>(Island, { rows: [] });
    await expect(last().actions.send('go')).resolves.toBeUndefined();

    renderIsland<Props>(Island, { rows: [] }, { reply: null });
    await expect(last().actions.send('go')).resolves.toBeUndefined();
  });

  test('send rejects with the reply error and field errors', async () => {
    renderIsland<Props>(
      Island,
      { rows: [] },
      { reply: { error: 'Nope', fieldErrors: { name: ["can't be blank"] } } }
    );

    await expect(last().actions.send('go')).rejects.toMatchObject({
      name: 'RequestError',
      message: 'Nope',
      fieldErrors: { name: ["can't be blank"] },
    });
  });

  test('request resolves with the reply', async () => {
    renderIsland<Props>(Island, { rows: [] }, { reply: { token: 'secret' } });

    await expect(last().actions.request('go')).resolves.toEqual({
      token: 'secret',
    });
  });

  test('pending calls reject when the LiveView disconnects', async () => {
    const { pushEvent } = renderIsland<Props>(Island, { rows: [] });
    pushEvent.mockReturnValue(new Promise(() => {}));
    const call = last().actions.send('go');

    window.dispatchEvent(
      new CustomEvent('phx:page-loading-start', { detail: { kind: 'error' } })
    );

    await expect(call).rejects.toThrow('Connection lost');
  });

  test('pending calls reject after the client timeout', async () => {
    vi.useFakeTimers();
    const { pushEvent } = renderIsland<Props>(Island, { rows: [] });
    pushEvent.mockReturnValue(new Promise(() => {}));
    const call = last().actions.send('go');

    vi.advanceTimersByTime(30_000);

    await expect(call).rejects.toThrow('did not answer');
  });

  test('navigate patches own routes and redirects elsewhere', () => {
    const { navigate, redirect } = renderIsland<Props>(Island, { rows: [] });

    last().actions.navigate('/things/42');
    last().actions.navigate('/other');

    expect(navigate).toHaveBeenCalledWith('/things/42', undefined);
    expect(redirect).toHaveBeenCalledWith('/other', undefined);
  });

  test('the page gets the props useProps returns', async () => {
    const { pushEvent } = renderIsland<Props>(Island, { rows: [{ id: 'a' }] });

    await userEvent.click(screen.getByRole('button', { name: '1 rows' }));

    expect(pushEvent).toHaveBeenCalledWith('go', {});
  });
});
