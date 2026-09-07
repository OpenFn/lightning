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
import * as useSessionContextModule from '../../../js/collaborative-editor/hooks/useSessionContext';
import * as notificationsModule from '../../../js/collaborative-editor/lib/notifications';
import type { Version } from '../../../js/collaborative-editor/types/sessionContext';

// Mock the hooks
const mockUseVersions = vi.spyOn(useSessionContextModule, 'useVersions');
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

    test('renders button with version number when viewing old snapshot', () => {
      render(
        <VersionDropdown
          currentVersion={3}
          latestVersion={5}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      // Should show version number (first 7 chars)
      const button = screen.getByRole('button');
      expect(button).toHaveTextContent('v3');
      expect(button).toHaveClass('bg-yellow-100', 'text-yellow-800');
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

    test('does not refetch if versions already loaded', async () => {
      const user = userEvent.setup();

      const mockVersions: Version[] = [
        createMockVersion({
          lock_version: 5,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          lock_version: 4,
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: false,
        }),
      ];

      mockUseVersions.mockReturnValue(mockVersions);
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
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          version_number: 2,
          lock_version: 20,
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: false,
        }),
        createMockVersion({
          version_number: 1,
          lock_version: 10,
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
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          version_number: 1,
          kind: 'go_live',
          published_by: 'Grace Hopper',
          source_project: null,
          lock_version: 10,
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

    test('shows "No versions available" when versions array is empty', async () => {
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
        expect(screen.getByText('No versions available')).toBeInTheDocument();
      });
    });

    test('shows the absolute date for each release', async () => {
      const user = userEvent.setup();

      const mockVersions: Version[] = [
        createMockVersion({
          version_number: 1,
          lock_version: 20,
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
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          version_number: 1,
          lock_version: 22,
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
      expect(selectedButton).toHaveClass('bg-primary-50', 'text-primary-900');
      expect(selectedButton?.querySelector('.hero-check')).toBeInTheDocument();

      // The newest row is NOT active while pinned to an older version
      const newestButton = screen
        .getAllByRole('menuitem')
        .find(btn => btn.textContent?.includes('v3'));
      expect(newestButton?.querySelector('.hero-check')).not.toBeInTheDocument();
    });

    test('marks the newest row when unpinned (following live)', async () => {
      const user = userEvent.setup();

      const mockVersions: Version[] = [
        createMockVersion({
          version_number: 3,
          lock_version: 30,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          version_number: 2,
          lock_version: 20,
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
      expect(newestButton).toHaveClass('bg-primary-50', 'text-primary-900');
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
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          version_number: 4,
          lock_version: 40,
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
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          version_number: 1,
          lock_version: 30,
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
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          lock_version: 1,
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
