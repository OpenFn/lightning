/**
 * VersionDropdown Component Tests
 *
 * Tests for VersionDropdown component that manages workflow version selection.
 *
 * Test Coverage:
 * - Renders with loading state initially
 * - Fetches versions when dropdown opens
 * - Displays versions after successful fetch
 * - Does not refetch if versions already loaded
 * - Shows error toast when versionsError is set
 * - Handles version selection correctly
 * - Newest release returns to live (clears ?v=); older releases pin by version_number
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
import type { Version } from '../../../js/collaborative-editor/types/sessionContext';

// Mock the hooks
const mockUseVersions = vi.spyOn(useSessionContextModule, 'useVersions');
const mockUseRunVersionNumber = vi.spyOn(
  useHistoryModule,
  'useRunVersionNumber'
);
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

// Mock version data factory matching the release payload shape
const createMockVersion = (overrides?: Partial<Version>): Version => ({
  version_number: 1,
  kind: 'go_live',
  inserted_at: '2024-01-13T10:30:00Z',
  published_by: 'Test User',
  source_project: null,
  lock_version: 1,
  restored_from_version_number: null,
  is_latest: false,
  ...overrides,
});

describe('VersionDropdown', () => {
  const mockRequestVersions = vi.fn();
  const mockOnVersionSelect = vi.fn();

  // Pin a version by driving the shared URL store through the patched
  // history.pushState (?v= now carries a version_number, e.g. ?v=1).
  const pinVersion = (versionNumber: number) => {
    window.history.pushState({}, '', `/?v=${versionNumber}`);
  };

  beforeEach(() => {
    vi.clearAllMocks();

    // Default mock implementations
    mockUseVersions.mockReturnValue([]);
    mockUseRunVersionNumber.mockReturnValue(undefined);
    mockUseVersionsLoaded.mockReturnValue(false);
    mockUseVersionsLoading.mockReturnValue(false);
    mockUseVersionsError.mockReturnValue(null);
    mockUseRequestVersions.mockReturnValue(mockRequestVersions);
  });

  afterEach(() => {
    // Reset the URL so a pinned ?v= does not leak into the next test.
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
      // The store's lock_version can lag the latest snapshot for a moment after
      // a save. With no pin in the URL the client is on the live document
      // regardless, and the chip used to render the stale lock_version as
      // "v3", a release number that may not exist at all.
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
      mockUseRunVersionNumber.mockReturnValue(2);

      // The document is that run's snapshot. What names it is the release the
      // run executed against, not the document's lock_version, which used to
      // be rendered as v3 whether or not any such release existed.
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
      mockUseRunVersionNumber.mockReturnValue(null);

      // Not "Draft": the lifecycle badge beside this uses that word for a
      // workflow that is not live, and this is about the content.
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

  describe('fetching versions', () => {
    test('fetches versions when dropdown opens for the first time', async () => {
      const user = userEvent.setup();

      mockUseVersions.mockReturnValue([]);
      mockUseVersionsLoading.mockReturnValue(false);

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

      // Should call requestVersions
      expect(mockRequestVersions).toHaveBeenCalledOnce();
    });

    test('asks once when the workflow has never been published', async () => {
      const user = userEvent.setup();

      let loaded = false;
      let loading = false;
      mockUseVersions.mockReturnValue([]);
      mockUseVersionsLoaded.mockImplementation(() => loaded);
      mockUseVersionsLoading.mockImplementation(() => loading);
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

      // The request is in flight.
      rerender(<VersionDropdown {...props} />);

      // It comes back with nothing, because this workflow has never been
      // published. An empty list is the answer, not the absence of one:
      // asking again because the list is empty asks again every time the
      // in-flight flag drops, which never stopped and left the panel saying it
      // was loading for good.
      loading = false;
      loaded = true;
      rerender(<VersionDropdown {...props} />);

      expect(mockRequestVersions).toHaveBeenCalledOnce();
      expect(screen.getByText('No published versions')).toBeInTheDocument();
    });

    test('does not refetch if versions already loaded', async () => {
      const user = userEvent.setup();

      const mockVersions: Version[] = [
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

      mockUseVersions.mockReturnValue(mockVersions);
      mockUseVersionsLoaded.mockReturnValue(true);
      mockUseVersionsLoading.mockReturnValue(false);

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

      // Should NOT call requestVersions (versions already loaded)
      expect(mockRequestVersions).not.toHaveBeenCalled();
    });

    test('does not fetch if already loading', async () => {
      const user = userEvent.setup();

      mockUseVersions.mockReturnValue([]);
      mockUseVersionsLoading.mockReturnValue(true);

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

      // Should NOT call requestVersions (already loading)
      expect(mockRequestVersions).not.toHaveBeenCalled();
    });

    test('shows loading message while fetching', async () => {
      const user = userEvent.setup();

      mockUseVersions.mockReturnValue([]);
      mockUseVersionsLoading.mockReturnValue(true);

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

  describe('displaying versions', () => {
    test('displays versions after successful fetch', async () => {
      const user = userEvent.setup();

      const mockVersions: Version[] = [
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

      mockUseVersions.mockReturnValue(mockVersions);

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

      // Should display each release by its version_number, with no "latest"
      // pseudo-row or badge inside the list (the concept has neither). The
      // trigger button may still read "latest" for the live state.
      const menu = screen.getByRole('menu');
      expect(within(menu).queryByText('latest')).not.toBeInTheDocument();
      expect(screen.getByText('v3')).toBeInTheDocument();
      expect(screen.getByText('v2')).toBeInTheDocument();
      expect(screen.getByText('v1')).toBeInTheDocument();
    });

    test('renders eyebrow title, action line, author, and promote source', async () => {
      const user = userEvent.setup();

      const mockVersions: Version[] = [
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

      mockUseVersions.mockReturnValue(mockVersions);

      render(
        <VersionDropdown
          currentVersion={20}
          latestVersion={20}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      await user.click(screen.getByRole('button'));

      // Eyebrow title
      expect(screen.getByText('Version history')).toBeInTheDocument();

      // Kind is conveyed by the action line, not a neutral badge
      expect(screen.queryByText('Promoted')).not.toBeInTheDocument();
      expect(screen.queryByText('Go live')).not.toBeInTheDocument();

      // Line 1 (action): promote reads "Promoted sandbox {sandbox}" (source is
      // bold); the author now stands alone on line 2, so "by" is gone.
      const promoteRow = screen.getByText('v2').closest('button');
      expect(promoteRow).toHaveTextContent('Promoted sandbox sandy-sandbox');
      expect(promoteRow).not.toHaveTextContent('by');
      expect(screen.getByText('sandy-sandbox')).toBeInTheDocument();

      // First release reads "Initial go-live" on line 1
      const goLiveRow = screen.getByText('v1').closest('button');
      expect(goLiveRow).toHaveTextContent('Initial go-live');

      // Line 2 (secondary): author full name as its own text, no avatar
      expect(screen.getByText('Ada Lovelace')).toBeInTheDocument();
      expect(screen.getByText('Grace Hopper')).toBeInTheDocument();
      expect(screen.queryByText('AL')).not.toBeInTheDocument();
      expect(screen.queryByText('GH')).not.toBeInTheDocument();
    });

    test('later go-live reads "Published from draft" rather than "Initial go-live"', async () => {
      const user = userEvent.setup();

      mockUseVersions.mockReturnValue([
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

      mockUseVersions.mockReturnValue([
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

      // No author line; just the action and the date
      const row = screen.getByText('v1').closest('button');
      expect(row).toHaveTextContent('Initial go-live');
      expect(row).toHaveTextContent('14 Jan 2024');
    });

    test('shows "No published versions" when nothing has been published', async () => {
      const user = userEvent.setup();

      mockUseVersions.mockReturnValue([]);
      mockUseVersionsLoading.mockReturnValue(false);

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

      const mockVersions: Version[] = [
        createMockVersion({
          version_number: 1,
          lock_version: 20,
          restored_from_version_number: null,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
      ];

      mockUseVersions.mockReturnValue(mockVersions);

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

      // Absolute date is rendered (not relative "... ago")
      expect(screen.getByText('15 Jan 2024')).toBeInTheDocument();
      expect(screen.queryByText(/ago$/)).not.toBeInTheDocument();
    });

    test('marks the pinned row by version_number (not lock_version)', async () => {
      const user = userEvent.setup();

      // v1's snapshot lock_version (22) deliberately differs from its
      // version_number (1) to prove the checkmark keys on version_number.
      const mockVersions: Version[] = [
        createMockVersion({
          version_number: 3,
          lock_version: 30,
          restored_from_version_number: null,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          version_number: 1,
          lock_version: 22,
          restored_from_version_number: null,
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: false,
        }),
      ];

      mockUseVersions.mockReturnValue(mockVersions);

      // Pinned to version_number 1 via ?v=1
      pinVersion(1);

      render(
        <VersionDropdown
          currentVersion={22}
          latestVersion={30}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      // Trigger button reads v{?v} directly (the version_number, not v22)
      const button = screen.getByRole('button');
      expect(button).toHaveTextContent('v1');
      expect(button).not.toHaveTextContent('v22');

      // Open dropdown
      await user.click(button);

      // The v1 row (the pinned release) is active with a checkmark
      const selectedButton = screen
        .getAllByRole('menuitem')
        .find(btn => btn.textContent?.includes('v1'));
      // The row highlight sits on the wrapper, which also holds the per-row
      // Restore action; the text colour stays on the pinning button.
      expect(selectedButton).toHaveClass('text-primary-900');
      expect(selectedButton?.parentElement).toHaveClass('bg-primary-50');
      expect(selectedButton?.querySelector('.hero-check')).toBeInTheDocument();

      // The newest row is NOT active while pinned to an older version
      const newestButton = screen
        .getAllByRole('menuitem')
        .find(btn => btn.textContent?.includes('v3'));
      expect(
        newestButton?.querySelector('.hero-check')
      ).not.toBeInTheDocument();
    });

    test('marks the newest row when unpinned (following live)', async () => {
      const user = userEvent.setup();

      const mockVersions: Version[] = [
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
      ];

      mockUseVersions.mockReturnValue(mockVersions);

      // No ?v= pin (afterEach resets the URL)
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

    test('newest release is the first row with a green v-pill and no "latest" text', async () => {
      const user = userEvent.setup();

      const mockVersions: Version[] = [
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

      mockUseVersions.mockReturnValue(mockVersions);

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

      // First menuitem is the newest release (v5), the second is the older (v4);
      // there is no separate "latest" pseudo-row.
      const versionButtons = screen.getAllByRole('menuitem');
      expect(versionButtons[0]).toHaveTextContent('v5');
      expect(versionButtons[1]).toHaveTextContent('v4');

      // Newest v-pill is green; older v-pill is neutral gray
      const newestPill = screen.getByText('v5');
      expect(newestPill).toHaveClass('bg-green-100', 'text-green-800');
      const olderPill = screen.getByText('v4');
      expect(olderPill).toHaveClass('bg-gray-100', 'text-gray-600');
    });
  });

  describe('version selection', () => {
    test('calls onVersionSelect with "latest" when latest version clicked', async () => {
      const user = userEvent.setup();

      const mockVersions: Version[] = [
        createMockVersion({
          lock_version: 5,
          restored_from_version_number: null,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
      ];

      mockUseVersions.mockReturnValue(mockVersions);

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

      const mockVersions: Version[] = [
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

      mockUseVersions.mockReturnValue(mockVersions);

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

      // Click the older release (displayed as v1, lock_version 30). Pinning now
      // uses version_number (1), which is what ?v= carries, NOT lock_version.
      const oldVersionButton = screen.getByText('v1').closest('button');
      expect(oldVersionButton).not.toBeNull();
      await user.click(oldVersionButton!);

      // Should call onVersionSelect with version_number (1), not lock_version (30)
      expect(mockOnVersionSelect).toHaveBeenCalledWith(1);
    });

    test('closes dropdown after version selection', async () => {
      const user = userEvent.setup();

      const mockVersions: Version[] = [
        createMockVersion({
          lock_version: 5,
          restored_from_version_number: null,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
      ];

      mockUseVersions.mockReturnValue(mockVersions);

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
    test('shows error toast when versionsError is set', async () => {
      mockUseVersionsError.mockReturnValue('Failed to load versions');

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

    test('shows error message in dropdown when versionsError is set', async () => {
      const user = userEvent.setup();

      mockUseVersions.mockReturnValue([]);
      mockUseVersionsLoading.mockReturnValue(false);
      mockUseVersionsError.mockReturnValue('Connection failed');

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

      mockUseVersions.mockReturnValue([]);
      mockUseVersionsLoading.mockReturnValue(false);
      mockUseVersionsError.mockReturnValue('Error message');

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
    // Three releases, newest first, matching what the channel sends.
    const threeVersions = () => {
      mockUseVersions.mockReturnValue([
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

      // The newest release is what is live, so there is nothing to put back.
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

      // Two separate actions on one row: reading it and putting it back.
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

      mockUseVersions.mockReturnValue([
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

      mockUseVersions.mockReturnValue([
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

      // Each release is one menuitem; there is no "latest" pseudo-row
      const menuItems = screen.getAllByRole('menuitem');
      expect(menuItems).toHaveLength(2);
    });
  });
});
