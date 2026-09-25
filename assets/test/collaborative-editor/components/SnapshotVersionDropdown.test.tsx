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
    window.history.pushState({}, '', '/?v=5');

    renderPicker(5, 7);

    expect(screen.getByRole('button')).toHaveTextContent('v5');
  });

  test('asks once for a workflow with no saves, rather than forever', async () => {
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

  test('asks again when a save clears the list under an open menu', async () => {
    const user = userEvent.setup();
    mockUseVersionsLoaded.mockReturnValue(true);
    mockUseVersions.mockReturnValue([snapshot(7, true)]);

    const { rerender } = render(
      <SnapshotVersionDropdown
        currentVersion={7}
        latestVersion={7}
        onVersionSelect={onVersionSelect}
      />
    );

    await user.click(screen.getByRole('button'));

    expect(requestVersions).not.toHaveBeenCalled();

    mockUseVersionsLoaded.mockReturnValue(false);
    mockUseVersions.mockReturnValue([]);
    rerender(
      <SnapshotVersionDropdown
        currentVersion={7}
        latestVersion={7}
        onVersionSelect={onVersionSelect}
      />
    );

    expect(requestVersions).toHaveBeenCalledTimes(1);
  });

  test('still retries when the menu is reopened mid-flight', async () => {
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

    mockUseVersionsLoading.mockReturnValue(true);
    rerender(
      <SnapshotVersionDropdown
        currentVersion={7}
        latestVersion={7}
        onVersionSelect={onVersionSelect}
      />
    );
    await user.click(screen.getByRole('button'));
    await user.click(screen.getByRole('button'));

    mockUseVersionsLoading.mockReturnValue(false);
    mockUseVersionsLoaded.mockReturnValue(true);
    mockUseVersionsError.mockReturnValue('Failed to load versions');
    rerender(
      <SnapshotVersionDropdown
        currentVersion={7}
        latestVersion={7}
        onVersionSelect={onVersionSelect}
      />
    );

    expect(requestVersions).toHaveBeenCalledTimes(2);
  });

  test('asks again next time it opens after a failed request', async () => {
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

    mockUseVersionsLoaded.mockReturnValue(true);
    mockUseVersionsError.mockReturnValue('Failed to load versions');
    rerender(
      <SnapshotVersionDropdown
        currentVersion={7}
        latestVersion={7}
        onVersionSelect={onVersionSelect}
      />
    );

    expect(requestVersions).toHaveBeenCalledTimes(1);

    await user.click(screen.getByRole('button'));
    await user.click(screen.getByRole('button'));

    expect(requestVersions).toHaveBeenCalledTimes(2);
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
