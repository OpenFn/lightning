/**
 * VersionDropdown Component Tests
 *
 * Tests for VersionDropdown component that manages workflow version selection.
 *
 * Test Coverage:
 * - Renders with loading state initially
 * - Fetches releases when dropdown opens
 * - Displays releases after successful fetch
 * - Does not refetch if releases already loaded
 * - Shows error toast when releasesError is set
 * - Handles version selection correctly
 * - Newest release returns to live (clears the pin); older releases pin by version_number
 * - Renders the "Version history" list: v-pill, initials avatar, kind sentence, absolute date
 * - Marks the currently-viewed row with a checkmark
 */

import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { VersionDropdown } from '../../../js/collaborative-editor/components/VersionDropdown';
import * as useHistoryModule from '../../../js/collaborative-editor/hooks/useHistory';
import * as useSessionContextModule from '../../../js/collaborative-editor/hooks/useSessionContext';
import * as notificationsModule from '../../../js/collaborative-editor/lib/notifications';
import type { Release } from '../../../js/collaborative-editor/types/sessionContext';

// Mock the hooks
const mockUseReleases = vi.spyOn(useSessionContextModule, 'useReleases');
const mockUseRunSummary = vi.spyOn(useHistoryModule, 'useRunSummary');
const mockUseLatestSnapshotId = vi.spyOn(
  useSessionContextModule,
  'useLatestSnapshotId'
);
const mockUseReleasesLoaded = vi.spyOn(
  useSessionContextModule,
  'useReleasesLoaded'
);
const mockUseReleasesLoading = vi.spyOn(
  useSessionContextModule,
  'useReleasesLoading'
);
const mockUseReleasesError = vi.spyOn(
  useSessionContextModule,
  'useReleasesError'
);
const mockUseRequestReleases = vi.spyOn(
  useSessionContextModule,
  'useRequestReleases'
);

// Mock notifications
const mockNotifications = {
  alert: vi.fn(),
  info: vi.fn(),
  success: vi.fn(),
  warning: vi.fn(),
};
vi.spyOn(notificationsModule, 'notifications', 'get').mockReturnValue(
  mockNotifications
);

const runSummary = (
  overrides: Partial<ReturnType<typeof baseRunSummary>> = {}
) => ({ ...baseRunSummary(), ...overrides });

const baseRunSummary = () => ({
  id: 'abcdef12-3456-7890-abcd-ef1234567890',
  state: 'success' as const,
  error_type: null,
  started_at: '2026-09-09T21:13:00Z',
  finished_at: '2026-09-09T21:13:01Z',
  version: 1,
  version_number: null as number | null,
  snapshot_id: null as string | null,
});

const createMockVersion = (overrides?: Partial<Release>): Release => ({
  version_number: 1,
  kind: 'go_live',
  inserted_at: '2024-01-13T10:30:00Z',
  published_by: 'Test User',
  source_project: null,
  lock_version: 1,
  snapshot_id: 'snapshot-1',
  restored_from_version_number: null,
  is_latest: false,
  ...overrides,
});

describe('VersionDropdown', () => {
  const mockRequestVersions = vi.fn();
  const mockOnVersionSelect = vi.fn();

  const pinVersion = (versionNumber: number) => {
    window.history.pushState({}, '', `/?release=${versionNumber}`);
  };

  beforeEach(() => {
    vi.clearAllMocks();

    // Default mock implementations
    mockUseReleases.mockReturnValue([]);
    mockUseRunSummary.mockReturnValue(undefined);
    mockUseLatestSnapshotId.mockReturnValue(null);
    mockUseReleasesLoaded.mockReturnValue(false);
    mockUseReleasesLoading.mockReturnValue(false);
    mockUseReleasesError.mockReturnValue(null);
    mockUseRequestReleases.mockReturnValue(mockRequestVersions);
  });

  afterEach(() => {
    window.history.pushState({}, '', '/');
  });

  describe('initial rendering', () => {
    test('renders button with loading placeholder when version info not loaded', () => {
      render(
        <VersionDropdown
          currentVersion={null}
          latestVersion={null}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      // Should show loading placeholder (•)
      const button = screen.getByRole('button');
      expect(button).toHaveTextContent('•');
      expect(button).toHaveClass('bg-gray-100', 'text-gray-600');
    });

    test('renders button with "latest" when viewing latest version', () => {
      render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      // Should show "latest" text
      const button = screen.getByRole('button');
      expect(button).toHaveTextContent('latest');
      expect(button).toHaveClass('bg-primary-100', 'text-primary-800');
    });

    test('reads "latest" on the live document, whatever the lock versions say', () => {
      render(
        <VersionDropdown
          currentVersion={3}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');
      expect(button).toHaveTextContent('latest');
      expect(button).not.toHaveTextContent('v3');
    });

    test('names the version a run executed against', () => {
      window.history.pushState(
        {},
        '',
        '/?as_run=abcdef12-3456-7890-abcd-ef1234567890'
      );
      mockUseRunSummary.mockReturnValue(
        runSummary({ version_number: 2, snapshot_id: 'snapshot-v2' })
      );

      render(
        <VersionDropdown
          currentVersion={3}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');
      expect(button).toHaveTextContent('v2');
      expect(button).toHaveClass('bg-yellow-100', 'text-yellow-800');
    });

    test('says unpublished for a run against content never published', () => {
      window.history.pushState(
        {},
        '',
        '/?as_run=abcdef12-3456-7890-abcd-ef1234567890'
      );
      mockUseRunSummary.mockReturnValue(
        runSummary({
          version_number: null,
          snapshot_id: 'snapshot-unpublished',
        })
      );

      render(
        <VersionDropdown
          currentVersion={3}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      expect(screen.getByRole('button')).toHaveTextContent('unpublished');
    });

    test('dropdown is closed by default', () => {
      render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      // Should not show dropdown menu
      expect(screen.queryByRole('menu')).not.toBeInTheDocument();
    });
  });

  describe('dropdown interactions', () => {
    test('opens dropdown when button is clicked', async () => {
      const user = userEvent.setup();

      render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');
      await user.click(button);

      // Dropdown should be open
      expect(screen.getByRole('menu')).toBeInTheDocument();
      expect(button).toHaveAttribute('aria-expanded', 'true');
    });

    test('closes dropdown when button is clicked again', async () => {
      const user = userEvent.setup();

      render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);
      expect(screen.getByRole('menu')).toBeInTheDocument();

      // Close dropdown
      await user.click(button);
      expect(screen.queryByRole('menu')).not.toBeInTheDocument();
    });

    test('closes dropdown when clicking outside', async () => {
      const user = userEvent.setup();

      render(
        <div>
          <div data-testid="outside">Outside</div>
          <VersionDropdown
            currentVersion={5}
            latestVersion={5}
            onVersionSelect={mockOnVersionSelect}
          />
        </div>
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);
      expect(screen.getByRole('menu')).toBeInTheDocument();

      // Click outside
      await user.click(screen.getByTestId('outside'));

      // Dropdown should close
      await waitFor(() => {
        expect(screen.queryByRole('menu')).not.toBeInTheDocument();
      });
    });

    test('closes dropdown when pressing Escape key', async () => {
      const user = userEvent.setup();

      render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);
      expect(screen.getByRole('menu')).toBeInTheDocument();

      // Press Escape
      await user.keyboard('{Escape}');

      // Dropdown should close
      await waitFor(() => {
        expect(screen.queryByRole('menu')).not.toBeInTheDocument();
      });
    });

    test('chevron icon rotates when dropdown is open', async () => {
      const user = userEvent.setup();

      const { container } = render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');
      const chevron = container.querySelector('.hero-chevron-down');

      // Initially not rotated
      expect(chevron).not.toHaveClass('rotate-180');

      // Open dropdown
      await user.click(button);

      // Chevron should rotate
      expect(chevron).toHaveClass('rotate-180');
    });
  });

  describe('fetching releases', () => {
    test('fetches releases when dropdown opens for the first time', async () => {
      const user = userEvent.setup();

      mockUseReleases.mockReturnValue([]);
      mockUseReleasesLoading.mockReturnValue(false);

      render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);

      expect(mockRequestVersions).toHaveBeenCalledOnce();
    });

    test('asks once when the workflow has never been published', async () => {
      const user = userEvent.setup();

      let loaded = false;
      let loading = false;
      mockUseReleases.mockReturnValue([]);
      mockUseReleasesLoaded.mockImplementation(() => loaded);
      mockUseReleasesLoading.mockImplementation(() => loading);
      mockRequestVersions.mockImplementation(() => {
        loading = true;
        return Promise.resolve();
      });

      const props = {
        currentVersion: 5,
        latestVersion: 5,
        onVersionSelect: mockOnVersionSelect,
      };

      const { rerender } = render(<VersionDropdown {...props} />);

      await user.click(screen.getByRole('button'));
      expect(mockRequestVersions).toHaveBeenCalledOnce();

      rerender(<VersionDropdown {...props} />);

      loading = false;
      loaded = true;
      rerender(<VersionDropdown {...props} />);

      expect(mockRequestVersions).toHaveBeenCalledOnce();
      expect(screen.getByText('No published versions')).toBeInTheDocument();
    });

    test('does not refetch if releases already loaded', async () => {
      const user = userEvent.setup();

      const mockVersions: Release[] = [
        createMockVersion({
          lock_version: 5,
          restored_from_version_number: null,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          lock_version: 4,
          restored_from_version_number: null,
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: false,
        }),
      ];

      mockUseReleases.mockReturnValue(mockVersions);
      mockUseReleasesLoaded.mockReturnValue(true);
      mockUseReleasesLoading.mockReturnValue(false);

      render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);

      expect(mockRequestVersions).not.toHaveBeenCalled();
    });

    test('asks again next time it opens after a failed request', async () => {
      const user = userEvent.setup();
      mockUseReleasesLoaded.mockReturnValue(false);

      const { rerender } = render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      await user.click(screen.getByRole('button'));
      expect(mockRequestVersions).toHaveBeenCalledTimes(1);

      mockUseReleasesLoaded.mockReturnValue(true);
      mockUseReleasesError.mockReturnValue('Failed to load versions');
      rerender(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      expect(mockRequestVersions).toHaveBeenCalledTimes(1);

      await user.click(screen.getByRole('button'));
      await user.click(screen.getByRole('button'));

      expect(mockRequestVersions).toHaveBeenCalledTimes(2);
    });

    test('still retries when the menu is reopened mid-flight', async () => {
      const user = userEvent.setup();
      mockUseReleasesLoaded.mockReturnValue(false);

      const { rerender } = render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      await user.click(screen.getByRole('button'));
      expect(mockRequestVersions).toHaveBeenCalledTimes(1);

      mockUseReleasesLoading.mockReturnValue(true);
      rerender(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );
      await user.click(screen.getByRole('button'));
      await user.click(screen.getByRole('button'));

      mockUseReleasesLoading.mockReturnValue(false);
      mockUseReleasesLoaded.mockReturnValue(true);
      mockUseReleasesError.mockReturnValue('Failed to load versions');
      rerender(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      expect(mockRequestVersions).toHaveBeenCalledTimes(2);
    });

    test('asks again when a save clears the list under an open menu', async () => {
      const user = userEvent.setup();
      mockUseReleasesLoaded.mockReturnValue(true);
      mockUseReleases.mockReturnValue([createMockVersion()]);

      const { rerender } = render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      await user.click(screen.getByRole('button'));
      expect(mockRequestVersions).not.toHaveBeenCalled();

      mockUseReleasesLoaded.mockReturnValue(false);
      mockUseReleases.mockReturnValue([]);
      rerender(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      expect(mockRequestVersions).toHaveBeenCalledTimes(1);
    });

    test('does not fetch if already loading', async () => {
      const user = userEvent.setup();

      mockUseReleases.mockReturnValue([]);
      mockUseReleasesLoading.mockReturnValue(true);

      render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);

      expect(mockRequestVersions).not.toHaveBeenCalled();
    });

    test('shows loading message while fetching', async () => {
      const user = userEvent.setup();

      mockUseReleases.mockReturnValue([]);
      mockUseReleasesLoading.mockReturnValue(true);

      render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);

      // Should show loading message
      expect(screen.getByText('Loading versions...')).toBeInTheDocument();
    });
  });

  describe('displaying releases', () => {
    test('displays releases after successful fetch', async () => {
      const user = userEvent.setup();

      const mockVersions: Release[] = [
        createMockVersion({
          version_number: 3,
          lock_version: 30,
          restored_from_version_number: null,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          version_number: 2,
          lock_version: 20,
          restored_from_version_number: null,
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: false,
        }),
        createMockVersion({
          version_number: 1,
          lock_version: 10,
          restored_from_version_number: null,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: false,
        }),
      ];

      mockUseReleases.mockReturnValue(mockVersions);

      render(
        <VersionDropdown
          currentVersion={30}
          latestVersion={30}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);

      const menu = screen.getByRole('menu');
      expect(within(menu).queryByText('latest')).not.toBeInTheDocument();
      expect(screen.getByText('v3')).toBeInTheDocument();
      expect(screen.getByText('v2')).toBeInTheDocument();
      expect(screen.getByText('v1')).toBeInTheDocument();
    });

    test('renders eyebrow title, action line, author, and promote source', async () => {
      const user = userEvent.setup();

      const mockVersions: Release[] = [
        createMockVersion({
          version_number: 2,
          kind: 'promote',
          published_by: 'Ada Lovelace',
          source_project: 'sandy-sandbox',
          lock_version: 20,
          restored_from_version_number: null,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          version_number: 1,
          kind: 'go_live',
          published_by: 'Grace Hopper',
          source_project: null,
          lock_version: 10,
          restored_from_version_number: null,
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: false,
        }),
      ];

      mockUseReleases.mockReturnValue(mockVersions);

      render(
        <VersionDropdown
          currentVersion={20}
          latestVersion={20}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      await user.click(screen.getByRole('button'));

      expect(screen.getByText('Version history')).toBeInTheDocument();

      expect(screen.queryByText('Promoted')).not.toBeInTheDocument();
      expect(screen.queryByText('Go live')).not.toBeInTheDocument();

      const promoteRow = screen.getByText('v2').closest('button');
      expect(promoteRow).toHaveTextContent('Promoted sandbox sandy-sandbox');
      expect(promoteRow).not.toHaveTextContent('by');
      expect(screen.getByText('sandy-sandbox')).toBeInTheDocument();

      const goLiveRow = screen.getByText('v1').closest('button');
      expect(goLiveRow).toHaveTextContent('Initial go-live');

      expect(screen.getByText('Ada Lovelace')).toBeInTheDocument();
      expect(screen.getByText('Grace Hopper')).toBeInTheDocument();
      expect(screen.queryByText('AL')).not.toBeInTheDocument();
      expect(screen.queryByText('GH')).not.toBeInTheDocument();
    });

    test('later go-live reads "Published from draft" rather than "Initial go-live"', async () => {
      const user = userEvent.setup();

      mockUseReleases.mockReturnValue([
        createMockVersion({
          version_number: 3,
          kind: 'go_live',
          published_by: 'Alan Turing',
          lock_version: 30,
          restored_from_version_number: null,
          inserted_at: '2024-01-16T10:30:00Z',
          is_latest: true,
        }),
      ]);

      render(
        <VersionDropdown
          currentVersion={30}
          latestVersion={30}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      await user.click(screen.getByRole('button'));

      const row = screen.getByText('v3').closest('button');
      expect(row).toHaveTextContent('Published from draft');
      expect(screen.getByText('Alan Turing')).toBeInTheDocument();
      expect(screen.queryByText(/Initial go-live/)).not.toBeInTheDocument();
    });

    test('omits the author line when published_by is null, keeping the date', async () => {
      const user = userEvent.setup();

      mockUseReleases.mockReturnValue([
        createMockVersion({
          version_number: 1,
          kind: 'go_live',
          published_by: null,
          lock_version: 10,
          restored_from_version_number: null,
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: true,
        }),
      ]);

      render(
        <VersionDropdown
          currentVersion={10}
          latestVersion={10}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      await user.click(screen.getByRole('button'));

      const row = screen.getByText('v1').closest('button');
      expect(row).toHaveTextContent('Initial go-live');
      expect(row).toHaveTextContent('14 Jan 2024');
    });

    test('offers a way back to Latest when nothing has been published', async () => {
      const user = userEvent.setup();

      mockUseReleases.mockReturnValue([]);

      render(
        <VersionDropdown
          currentVersion={3}
          latestVersion={7}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      await user.click(screen.getByRole('button'));
      await user.click(screen.getByTestId('version-latest'));

      expect(mockOnVersionSelect).toHaveBeenCalledWith('latest');
    });

    test('offers Latest, and says nothing is published yet', async () => {
      const user = userEvent.setup();

      mockUseReleases.mockReturnValue([]);
      mockUseReleasesLoading.mockReturnValue(false);

      render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown (this will trigger fetch, but we mock empty response)
      await user.click(button);

      // Wait for loading to complete
      await waitFor(() => {
        expect(screen.getByText('No published versions')).toBeInTheDocument();
      });
    });

    test('shows the absolute date for each release', async () => {
      const user = userEvent.setup();

      const mockVersions: Release[] = [
        createMockVersion({
          version_number: 1,
          lock_version: 20,
          restored_from_version_number: null,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
      ];

      mockUseReleases.mockReturnValue(mockVersions);

      render(
        <VersionDropdown
          currentVersion={20}
          latestVersion={20}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);

      expect(screen.getByText('15 Jan 2024')).toBeInTheDocument();
      expect(screen.queryByText(/ago$/)).not.toBeInTheDocument();
    });

    test('marks the pinned row by version_number (not lock_version)', async () => {
      const user = userEvent.setup();

      const mockVersions: Release[] = [
        createMockVersion({
          version_number: 3,
          lock_version: 30,
          snapshot_id: 'snapshot-v3',
          restored_from_version_number: null,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          version_number: 1,
          lock_version: 22,
          snapshot_id: 'snapshot-v1',
          restored_from_version_number: null,
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: false,
        }),
      ];

      mockUseReleases.mockReturnValue(mockVersions);

      pinVersion(1);

      render(
        <VersionDropdown
          currentVersion={22}
          latestVersion={30}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');
      expect(button).toHaveTextContent('v1');
      expect(button).not.toHaveTextContent('v22');

      // Open dropdown
      await user.click(button);

      const selectedButton = screen
        .getAllByRole('menuitem')
        .find(btn => btn.textContent?.includes('v1'));
      expect(selectedButton).toHaveClass('text-primary-900');
      expect(selectedButton?.parentElement).toHaveClass('bg-primary-50');
      expect(selectedButton?.querySelector('.hero-check')).toBeInTheDocument();

      const newestButton = screen
        .getAllByRole('menuitem')
        .find(btn => btn.textContent?.includes('v3'));
      expect(
        newestButton?.querySelector('.hero-check')
      ).not.toBeInTheDocument();
    });

    test('marks the row holding the live content', async () => {
      const user = userEvent.setup();

      const mockVersions: Release[] = [
        createMockVersion({
          version_number: 3,
          lock_version: 30,
          snapshot_id: 'snapshot-v3',
          restored_from_version_number: null,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          version_number: 2,
          lock_version: 20,
          snapshot_id: 'snapshot-v2',
          restored_from_version_number: null,
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: false,
        }),
      ];

      mockUseReleases.mockReturnValue(mockVersions);
      mockUseLatestSnapshotId.mockReturnValue('snapshot-v3');

      render(
        <VersionDropdown
          currentVersion={30}
          latestVersion={30}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      await user.click(screen.getByRole('button'));

      const newestButton = screen
        .getAllByRole('menuitem')
        .find(btn => btn.textContent?.includes('v3'));
      expect(newestButton).toHaveClass('text-primary-900');
      expect(newestButton?.parentElement).toHaveClass('bg-primary-50');
      expect(newestButton?.querySelector('.hero-check')).toBeInTheDocument();

      const olderButton = screen
        .getAllByRole('menuitem')
        .find(btn => btn.textContent?.includes('v2'));
      expect(olderButton?.querySelector('.hero-check')).not.toBeInTheDocument();
    });

    test('marks nothing when the live content has moved past the last publish', async () => {
      const user = userEvent.setup();

      mockUseReleases.mockReturnValue([
        createMockVersion({
          version_number: 3,
          lock_version: 30,
          snapshot_id: 'snapshot-v3',
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
      ]);
      mockUseLatestSnapshotId.mockReturnValue('snapshot-since-v3');

      render(
        <VersionDropdown
          currentVersion={31}
          latestVersion={31}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      await user.click(screen.getByRole('button'));

      const row = screen
        .getAllByRole('menuitem')
        .find(btn => btn.textContent?.includes('v3'));
      expect(row?.querySelector('.hero-check')).not.toBeInTheDocument();
    });

    test('marks the row a run executed, in a run view', async () => {
      const user = userEvent.setup();

      window.history.pushState(
        {},
        '',
        '/?as_run=abcdef12-3456-7890-abcd-ef1234567890'
      );

      mockUseReleases.mockReturnValue([
        createMockVersion({
          version_number: 3,
          lock_version: 30,
          snapshot_id: 'snapshot-v3',
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          version_number: 2,
          lock_version: 20,
          snapshot_id: 'snapshot-v2',
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: false,
        }),
      ]);
      mockUseLatestSnapshotId.mockReturnValue('snapshot-v3');
      mockUseRunSummary.mockReturnValue(
        runSummary({ version_number: 2, snapshot_id: 'snapshot-v2' })
      );

      render(
        <VersionDropdown
          currentVersion={20}
          latestVersion={30}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      await user.click(screen.getByRole('button'));

      const ran = screen
        .getAllByRole('menuitem')
        .find(btn => btn.textContent?.includes('v2'));
      expect(ran?.querySelector('.hero-check')).toBeInTheDocument();

      const newest = screen
        .getAllByRole('menuitem')
        .find(btn => btn.textContent?.includes('v3'));
      expect(newest?.querySelector('.hero-check')).not.toBeInTheDocument();
    });

    test('Latest leads, then the publishes, newest with a green v-pill', async () => {
      const user = userEvent.setup();

      const mockVersions: Release[] = [
        createMockVersion({
          version_number: 5,
          lock_version: 50,
          restored_from_version_number: null,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          version_number: 4,
          lock_version: 40,
          restored_from_version_number: null,
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: false,
        }),
      ];

      mockUseReleases.mockReturnValue(mockVersions);

      render(
        <VersionDropdown
          currentVersion={50}
          latestVersion={50}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);

      const versionButtons = screen.getAllByRole('menuitem');
      expect(versionButtons[0]).toHaveTextContent('Latest');
      expect(versionButtons[1]).toHaveTextContent('v5');
      expect(versionButtons[2]).toHaveTextContent('v4');

      const newestPill = screen.getByText('v5');
      expect(newestPill).toHaveClass('bg-green-100', 'text-green-800');
      const olderPill = screen.getByText('v4');
      expect(olderPill).toHaveClass('bg-gray-100', 'text-gray-600');
    });
  });

  describe('version selection', () => {
    test('calls onVersionSelect with "latest" when latest version clicked', async () => {
      const user = userEvent.setup();

      const mockVersions: Release[] = [
        createMockVersion({
          lock_version: 5,
          restored_from_version_number: null,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
      ];

      mockUseReleases.mockReturnValue(mockVersions);

      render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);

      // Click latest version (use getAllByRole to find the menuitem)
      const menuItems = screen.getAllByRole('menuitem');
      const latestMenuItem = menuItems[0]; // First menuitem is the latest version
      await user.click(latestMenuItem);

      // Should call onVersionSelect with "latest"
      expect(mockOnVersionSelect).toHaveBeenCalledWith('latest');
    });

    test('calls onVersionSelect with version_number when old version clicked', async () => {
      const user = userEvent.setup();

      const mockVersions: Release[] = [
        createMockVersion({
          version_number: 2,
          lock_version: 50,
          restored_from_version_number: null,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          version_number: 1,
          lock_version: 30,
          restored_from_version_number: null,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: false,
        }),
      ];

      mockUseReleases.mockReturnValue(mockVersions);

      render(
        <VersionDropdown
          currentVersion={50}
          latestVersion={50}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);

      const oldVersionButton = screen.getByText('v1').closest('button');
      expect(oldVersionButton).not.toBeNull();
      await user.click(oldVersionButton!);

      expect(mockOnVersionSelect).toHaveBeenCalledWith(1);
    });

    test('closes dropdown after version selection', async () => {
      const user = userEvent.setup();

      const mockVersions: Release[] = [
        createMockVersion({
          lock_version: 5,
          restored_from_version_number: null,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
      ];

      mockUseReleases.mockReturnValue(mockVersions);

      render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);
      expect(screen.getByRole('menu')).toBeInTheDocument();

      // Click version (use getAllByRole to find the menuitem)
      const menuItems = screen.getAllByRole('menuitem');
      await user.click(menuItems[0]);

      // Dropdown should close
      await waitFor(() => {
        expect(screen.queryByRole('menu')).not.toBeInTheDocument();
      });
    });
  });

  describe('error handling', () => {
    test('shows error toast when releasesError is set', async () => {
      mockUseReleasesError.mockReturnValue('Failed to load versions');

      render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      // Should show error notification
      await waitFor(() => {
        expect(mockNotifications.alert).toHaveBeenCalledWith({
          title: 'Failed to load versions',
          description: 'Please try again',
        });
      });
    });

    test('shows error message in dropdown when releasesError is set', async () => {
      const user = userEvent.setup();

      mockUseReleases.mockReturnValue([]);
      mockUseReleasesLoading.mockReturnValue(false);
      mockUseReleasesError.mockReturnValue('Connection failed');

      render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);

      // Should show error message
      expect(screen.getByText('Connection failed')).toBeInTheDocument();
    });

    test('error message has correct styling', async () => {
      const user = userEvent.setup();

      mockUseReleases.mockReturnValue([]);
      mockUseReleasesLoading.mockReturnValue(false);
      mockUseReleasesError.mockReturnValue('Error message');

      render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);

      const errorText = screen.getByText('Error message');
      expect(errorText).toHaveClass('text-red-600');
    });
  });

  describe('restoring a version', () => {
    const threeVersions = () => {
      mockUseReleases.mockReturnValue([
        createMockVersion({
          version_number: 3,
          is_latest: true,
          lock_version: 3,
        }),
        createMockVersion({ version_number: 2, lock_version: 2 }),
        createMockVersion({ version_number: 1, lock_version: 1 }),
      ]);
    };

    const renderWithRestore = (onVersionRestore?: (v: number) => void) =>
      render(
        <VersionDropdown
          currentVersion={3}
          latestVersion={3}
          onVersionSelect={mockOnVersionSelect}
          {...(onVersionRestore && { onVersionRestore })}
        />
      );

    test('offers Restore on every version but the newest', async () => {
      const onVersionRestore = vi.fn();
      const user = userEvent.setup();
      threeVersions();

      renderWithRestore(onVersionRestore);
      await user.click(screen.getByRole('button'));

      expect(screen.queryByTestId('restore-version-3')).not.toBeInTheDocument();
      expect(screen.getByTestId('restore-version-2')).toBeInTheDocument();
      expect(screen.getByTestId('restore-version-1')).toBeInTheDocument();
    });

    test('asks to restore the version whose row was clicked', async () => {
      const onVersionRestore = vi.fn();
      const user = userEvent.setup();
      threeVersions();

      renderWithRestore(onVersionRestore);
      await user.click(screen.getByRole('button'));
      await user.click(screen.getByTestId('restore-version-2'));

      expect(onVersionRestore).toHaveBeenCalledWith(2);
    });

    test('restoring does not also pin the version', async () => {
      const onVersionRestore = vi.fn();
      const user = userEvent.setup();
      threeVersions();

      renderWithRestore(onVersionRestore);
      await user.click(screen.getByRole('button'));
      await user.click(screen.getByTestId('restore-version-2'));

      expect(mockOnVersionSelect).not.toHaveBeenCalled();
    });

    test('offers no Restore when the viewer cannot edit', async () => {
      const user = userEvent.setup();
      threeVersions();

      renderWithRestore();
      await user.click(screen.getByRole('button'));

      expect(screen.queryByTestId('restore-version-2')).not.toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    test('button has correct ARIA attributes', () => {
      render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Should have ARIA attributes
      expect(button).toHaveAttribute('aria-expanded', 'false');
      expect(button).toHaveAttribute('aria-haspopup', 'true');
    });

    test('button aria-expanded updates when dropdown opens', async () => {
      const user = userEvent.setup();

      render(
        <VersionDropdown
          currentVersion={5}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Initially closed
      expect(button).toHaveAttribute('aria-expanded', 'false');

      // Open dropdown
      await user.click(button);

      // Should be expanded
      expect(button).toHaveAttribute('aria-expanded', 'true');
    });

    test('dropdown menu has correct role attributes', async () => {
      const user = userEvent.setup();

      mockUseReleases.mockReturnValue([
        createMockVersion({
          lock_version: 1,
          restored_from_version_number: null,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        }),
      ]);

      render(
        <VersionDropdown
          currentVersion={1}
          latestVersion={1}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);

      // Menu should have correct role
      const menu = screen.getByRole('menu');
      expect(menu).toHaveAttribute('aria-orientation', 'vertical');
    });

    test('version items have menuitem role', async () => {
      const user = userEvent.setup();

      mockUseReleases.mockReturnValue([
        createMockVersion({
          lock_version: 2,
          restored_from_version_number: null,
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          lock_version: 1,
          restored_from_version_number: null,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: false,
        }),
      ]);

      render(
        <VersionDropdown
          currentVersion={2}
          latestVersion={2}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);

      const menuItems = screen.getAllByRole('menuitem');
      expect(menuItems).toHaveLength(3);
    });
  });
});
