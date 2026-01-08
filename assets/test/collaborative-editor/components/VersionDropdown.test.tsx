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
 * - Shows "latest" for current version when viewing latest
 * - Shows version number when viewing old snapshot
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';

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

// Mock version data factory
const createMockVersion = (overrides?: Partial<Version>): Version => ({
  lock_version: 1,
  inserted_at: '2024-01-13T10:30:00Z',
  is_latest: false,
  ...overrides,
});

describe('VersionDropdown', () => {
  const mockRequestVersions = vi.fn();
  const mockOnVersionSelect = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();

    // Default mock implementations
    mockUseVersions.mockReturnValue([]);
    mockUseVersionsLoading.mockReturnValue(false);
    mockUseVersionsError.mockReturnValue(null);
    mockUseRequestVersions.mockReturnValue(mockRequestVersions);
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
          lock_version: 3,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          lock_version: 2,
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: false,
        }),
        createMockVersion({
          lock_version: 1,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: false,
        }),
      ];

      mockUseVersions.mockReturnValue(mockVersions);

      render(
        <VersionDropdown
          currentVersion={3}
          latestVersion={3}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);

      // Should display all versions (use getAllByText for "latest" since it appears in button and menu)
      const latestElements = screen.getAllByText('latest');
      expect(latestElements.length).toBeGreaterThan(0);
      expect(screen.getByText('v2')).toBeInTheDocument();
      expect(screen.getByText('v1')).toBeInTheDocument();
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

    test('shows formatted timestamps for each version', async () => {
      const user = userEvent.setup();

      const mockVersions: Version[] = [
        createMockVersion({
          lock_version: 2,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
      ];

      mockUseVersions.mockReturnValue(mockVersions);

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

      // Should show formatted timestamp (appears twice: once for "latest" and once for "v2")
      const timestamp = new Date('2024-01-15T10:30:00Z').toLocaleString();
      const timestampElements = screen.getAllByText(timestamp);
      expect(timestampElements.length).toBe(2);
    });

    test('highlights currently selected version', async () => {
      const user = userEvent.setup();

      const mockVersions: Version[] = [
        createMockVersion({
          lock_version: 3,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          lock_version: 2,
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: false,
        }),
      ];

      mockUseVersions.mockReturnValue(mockVersions);

      render(
        <VersionDropdown
          currentVersion={2}
          latestVersion={3}
          onVersionSelect={mockOnVersionSelect}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);

      // Find the selected version (v2)
      const versionButtons = screen.getAllByRole('menuitem');
      const selectedButton = versionButtons.find(btn =>
        btn.textContent?.includes('v2')
      );

      // Should have selection styling
      expect(selectedButton).toHaveClass('bg-primary-50', 'text-primary-900');

      // Should show checkmark
      const checkmark = selectedButton?.querySelector('.hero-check');
      expect(checkmark).toBeInTheDocument();
    });

    test('shows "latest" for first item when viewing latest version', async () => {
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

      // First item should show "latest"
      const versionButtons = screen.getAllByRole('menuitem');
      expect(versionButtons[0]).toHaveTextContent('latest');

      // Second item should show version number (v5)
      expect(versionButtons[1]).toHaveTextContent('v5');

      // Third item should show version number (v4)
      expect(versionButtons[2]).toHaveTextContent('v4');
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

    test('calls onVersionSelect with lock_version when old version clicked', async () => {
      const user = userEvent.setup();

      const mockVersions: Version[] = [
        createMockVersion({
          lock_version: 5,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        createMockVersion({
          lock_version: 3,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: false,
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

      // Click old version (v3)
      const oldVersionButton = screen.getByText('v3').closest('button');
      expect(oldVersionButton).not.toBeNull();
      await user.click(oldVersionButton!);

      // Should call onVersionSelect with lock_version
      expect(mockOnVersionSelect).toHaveBeenCalledWith(3);
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

      // All version items should have menuitem role (1 "latest" + 2 versions)
      const menuItems = screen.getAllByRole('menuitem');
      expect(menuItems).toHaveLength(3);
    });
  });
});
