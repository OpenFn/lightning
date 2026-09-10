/**
 * Tests for the version picker a user without experimental features gets.
 *
 * It lists every saved snapshot, numbered by its own `lock_version`, and pins
 * one with `?v=`. The releases picker beside it lists the publish trail and
 * numbers by release, and the two build different collaboration rooms, so which
 * picker is on screen decides what a version number means for the whole
 * session.
 */

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { SnapshotVersionDropdown } from '../../../js/collaborative-editor/components/SnapshotVersionDropdown';
import * as useSessionContextModule from '../../../js/collaborative-editor/hooks/useSessionContext';
import type { Version } from '../../../js/collaborative-editor/types/sessionContext';

const mockUseVersions = vi.spyOn(useSessionContextModule, 'useVersions');
const mockUseVersionsLoaded = vi.spyOn(
  useSessionContextModule,
  'useVersionsLoaded'
);
const mockUseVersionsLoading = vi.spyOn(
  useSessionContextModule,
  'useVersionsLoading'
);
const mockUseVersionsError = vi.spyOn(
  useSessionContextModule,
  'useVersionsError'
);
const mockUseRequestVersions = vi.spyOn(
  useSessionContextModule,
  'useRequestVersions'
);

const requestVersions = vi.fn<() => Promise<void>>();
const onVersionSelect = vi.fn();

const snapshot = (lock_version: number, is_latest = false): Version => ({
  lock_version,
  inserted_at: '2026-01-13T10:30:00Z',
  is_latest,
});

const renderPicker = (current: number | null, latest: number | null) =>
  render(
    <SnapshotVersionDropdown
      currentVersion={current}
      latestVersion={latest}
      onVersionSelect={onVersionSelect}
    />
  );

describe('SnapshotVersionDropdown', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.history.pushState({}, '', '/');
    requestVersions.mockResolvedValue(undefined);
    mockUseVersions.mockReturnValue([]);
    mockUseVersionsLoaded.mockReturnValue(false);
    mockUseVersionsLoading.mockReturnValue(false);
    mockUseVersionsError.mockReturnValue(null);
    mockUseRequestVersions.mockReturnValue(requestVersions);
  });

  afterEach(() => {
    window.history.pushState({}, '', '/');
  });

  test('reads "latest" on the newest save with nothing pinned', () => {
    renderPicker(7, 7);

    expect(screen.getByRole('button')).toHaveTextContent('latest');
  });

  test('names the pinned save by its lock_version', () => {
    // Pinned to an older save, so the chip stops claiming to be latest.
    window.history.pushState({}, '', '/?v=5');

    renderPicker(5, 7);

    expect(screen.getByRole('button')).toHaveTextContent('v5');
  });

  test('asks once for a workflow with no saves, rather than forever', async () => {
    // A workflow that has never been saved answers with an empty list, and the
    // menu stays open on that answer. Keying the ask on the list being empty
    // rather than on having asked re-fires the effect every time the loading
    // flag settles, which asks again, which sets it loading again.
    const user = userEvent.setup();
    const { rerender } = render(
      <SnapshotVersionDropdown
        currentVersion={7}
        latestVersion={7}
        onVersionSelect={onVersionSelect}
      />
    );

    await user.click(screen.getByRole('button'));
    expect(requestVersions).toHaveBeenCalledTimes(1);

    // The request runs and comes back empty: loading goes up, then down, with
    // the list still empty and the menu still open.
    mockUseVersionsLoading.mockReturnValue(true);
    rerender(
      <SnapshotVersionDropdown
        currentVersion={7}
        latestVersion={7}
        onVersionSelect={onVersionSelect}
      />
    );

    mockUseVersionsLoading.mockReturnValue(false);
    mockUseVersionsLoaded.mockReturnValue(true);
    rerender(
      <SnapshotVersionDropdown
        currentVersion={7}
        latestVersion={7}
        onVersionSelect={onVersionSelect}
      />
    );

    expect(requestVersions).toHaveBeenCalledTimes(1);
  });

  test('lists the saves and pins the one clicked by its lock_version', async () => {
    const user = userEvent.setup();
    mockUseVersions.mockReturnValue([
      snapshot(7, true),
      snapshot(6),
      snapshot(5),
    ]);
    mockUseVersionsLoaded.mockReturnValue(true);

    renderPicker(7, 7);
    await user.click(screen.getByRole('button'));

    const rows = screen.getAllByRole('menuitem');
    // The newest row plus a "latest" row that unpins rather than pinning to
    // itself.
    expect(rows).toHaveLength(4);

    const five = rows.find(row => row.textContent?.includes('v5'));
    await user.click(five as HTMLElement);

    expect(onVersionSelect).toHaveBeenCalledWith(5);
  });

  test('clicking latest unpins rather than pinning the newest number', async () => {
    const user = userEvent.setup();
    mockUseVersions.mockReturnValue([snapshot(7, true), snapshot(6)]);
    mockUseVersionsLoaded.mockReturnValue(true);
    window.history.pushState({}, '', '/?v=6');

    renderPicker(6, 7);
    await user.click(screen.getByRole('button'));

    const latest = screen
      .getAllByRole('menuitem')
      .find(row => row.textContent?.includes('latest'));
    await user.click(latest as HTMLElement);

    expect(onVersionSelect).toHaveBeenCalledWith('latest');
  });

  test('says so when there is nothing to list', async () => {
    const user = userEvent.setup();
    mockUseVersionsLoaded.mockReturnValue(true);

    renderPicker(0, 0);
    await user.click(screen.getByRole('button'));

    expect(screen.getByText('No versions available')).toBeInTheDocument();
  });
});
