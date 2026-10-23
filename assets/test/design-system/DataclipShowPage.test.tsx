import { screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, test, vi } from 'vitest';

import {
  DataclipShowPage,
  type Props,
} from '../../js/design-system/pages/DataclipShowPage';

import { renderIsland } from './renderIsland';

const ID = '9a8b7c6d-3333-4a4a-8b8b-0123456789ab';

const props: Props = {
  project: { id: 'p1', parentId: null, color: null },
  projectLabel: 'Malawi HIV',
  dataclip: {
    id: ID,
    type: 'http_request',
    insertedAt: '2026-10-14T09:30:00Z',
    updatedAt: '2026-10-14T09:31:00Z',
    wipedAt: null,
  },
};

describe('DataclipShowPage', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  test('fetches the body from the dataclip controller and shows it', async () => {
    const fetchMock = vi.fn(() =>
      Promise.resolve(
        new Response('{"x":1}', {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      )
    );
    vi.stubGlobal('fetch', fetchMock);
    renderIsland<Props>(DataclipShowPage, props);
    expect(screen.getByText(ID)).toBeTruthy();
    await waitFor(() => expect(screen.getByText(/"x"/)).toBeTruthy());
    expect(fetchMock).toHaveBeenCalledWith(`/dataclip/body/${ID}`);
  });

  test('does not ask for the body of a wiped dataclip', () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    renderIsland<Props>(DataclipShowPage, {
      ...props,
      dataclip: { ...props.dataclip, wipedAt: '2026-10-20T00:00:00Z' },
    });
    expect(screen.getByText('No Data Available')).toBeTruthy();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
