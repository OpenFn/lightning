/**
 * Tests for AdaptorSelectionModal component
 *
 * Tests the modal that allows users to search and select adaptors
 * when creating new job nodes in the workflow canvas.
 */

import { KeyboardProvider } from '#/collaborative-editor/keyboard';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { AdaptorSelectionModal } from '../../../js/collaborative-editor/components/AdaptorSelectionModal';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import type { Adaptor } from '../../../js/collaborative-editor/types/adaptor';

// Mock useAdaptorIcons to avoid fetching icon manifest
vi.mock('#/workflow-diagram/useAdaptorIcons', () => ({
  default: () => null,
}));

// Mock adaptor data
const mockProjectAdaptors: Adaptor[] = [
  {
    name: '@openfn/language-http',
    latest_version: '1.0.0',
    versions: ['1.0.0', '0.9.0'],
    repository: 'git+https://github.com/openfn/adaptors.git',
    icon_urls: { square: null, rectangle: null },
  },
  {
    name: '@openfn/language-salesforce',
    latest_version: '2.1.0',
    versions: ['2.1.0', '2.0.0'],
    repository: 'git+https://github.com/openfn/adaptors.git',
    icon_urls: { square: null, rectangle: null },
  },
];

const mockAllAdaptors: Adaptor[] = [
  ...mockProjectAdaptors,
  {
    name: '@openfn/language-dhis2',
    latest_version: '3.2.1',
    versions: ['3.2.1', '3.2.0'],
    repository: 'git+https://github.com/openfn/adaptors.git',
    icon_urls: { square: null, rectangle: null },
  },
  {
    name: '@openfn/language-common',
    latest_version: '2.0.0',
    versions: ['2.0.0', '1.9.0'],
    repository: 'git+https://github.com/openfn/adaptors.git',
    icon_urls: { square: null, rectangle: null },
  },
];

// Mock store context with proper structure
function createMockStoreContext(
  isLoading = false,
  error: string | null = null
) {
  const snapshot = {
    adaptors: isLoading || error ? [] : mockAllAdaptors,
    projectAdaptors: mockProjectAdaptors,
    isLoading,
    error,
  };
  return {
    adaptorStore: {
      subscribe: vi.fn(() => vi.fn()),
      getSnapshot: vi.fn(() => snapshot),
      withSelector: vi.fn(selector => () => selector(snapshot)),
      requestAdaptors: vi.fn(),
      setAdaptors: vi.fn(),
      clearError: vi.fn(),
    },
    credentialStore: {
      subscribe: vi.fn(() => vi.fn()),
      getSnapshot: vi.fn(() => ({
        credentials: [],
        isLoading: false,
        error: null,
      })),
      withSelector: vi.fn(),
    },
    awarenessStore: {
      subscribe: vi.fn(() => vi.fn()),
      getSnapshot: vi.fn(() => ({ users: [] })),
      withSelector: vi.fn(),
    },
    workflowStore: {
      subscribe: vi.fn(() => vi.fn()),
      getSnapshot: vi.fn(() => ({ workflow: null })),
      withSelector: vi.fn(),
    },
    sessionContextStore: {
      subscribe: vi.fn(() => vi.fn()),
      getSnapshot: vi.fn(() => ({ context: null })),
      withSelector: vi.fn(),
    },
  };
}

function renderWithProviders(
  ui: React.ReactElement,
  mockStoreContext = createMockStoreContext()
) {
  return render(
    <KeyboardProvider>
      <StoreContext.Provider value={mockStoreContext as any}>
        {ui}
      </StoreContext.Provider>
    </KeyboardProvider>
  );
}

describe('AdaptorSelectionModal', () => {
  const onClose = vi.fn();
  const onSelect = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('modal visibility', () => {
    it('renders when open', () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          adaptorsInUse={mockProjectAdaptors}
        />
      );

      expect(
        screen.getByPlaceholderText('Search for an adaptor to connect...')
      ).toBeInTheDocument();
    });

    it('does not render when closed', () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={false}
          onClose={onClose}
          onSelect={onSelect}
        />
      );

      expect(
        screen.queryByPlaceholderText('Search for an adaptor to connect...')
      ).not.toBeInTheDocument();
    });

    it('shows a loading state instead of the search list while the catalogue is loading', () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          adaptorsInUse={[]}
        />,
        createMockStoreContext(true)
      );

      expect(screen.getByTestId('adaptor-list-loading')).toBeInTheDocument();
      expect(
        screen.queryByPlaceholderText('Search for an adaptor to connect...')
      ).not.toBeInTheDocument();
    });

    it('shows an error state with a retry affordance when the catalogue fetch fails', () => {
      const mockStoreContext = createMockStoreContext(false, 'Server error');

      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          adaptorsInUse={[]}
        />,
        mockStoreContext
      );

      expect(screen.getByTestId('adaptor-list-error')).toBeInTheDocument();
      expect(
        screen.queryByPlaceholderText('Search for an adaptor to connect...')
      ).not.toBeInTheDocument();

      fireEvent.click(screen.getByRole('button', { name: 'Retry' }));
      expect(
        mockStoreContext.adaptorStore.requestAdaptors
      ).toHaveBeenCalledTimes(1);
    });
  });

  describe('adaptor display', () => {
    it('displays project adaptors section with adaptors', () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          adaptorsInUse={mockProjectAdaptors}
        />
      );

      expect(screen.getByText('Adaptors in this project')).toBeInTheDocument();
      // Use getAllByText since adaptors appear in both sections
      expect(screen.getAllByText('Http').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Salesforce').length).toBeGreaterThan(0);
    });

    it('displays all adaptors section', () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          adaptorsInUse={mockProjectAdaptors}
        />
      );

      expect(screen.getByText('All adaptors')).toBeInTheDocument();
      expect(screen.getByText('Dhis2')).toBeInTheDocument();
      expect(screen.getByText('Common')).toBeInTheDocument();
    });

    it("shows 'Available adaptors' when no project adaptors", () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          adaptorsInUse={[]}
        />
      );

      expect(
        screen.queryByText('Adaptors in this project')
      ).not.toBeInTheDocument();
      expect(screen.getByText('Available adaptors')).toBeInTheDocument();
    });

    it('displays adaptor version in description', () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          adaptorsInUse={mockProjectAdaptors}
        />
      );

      // Use getAllByText since adaptors may appear in both project and all sections
      expect(screen.getAllByText('Latest: 1.0.0').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Latest: 2.1.0').length).toBeGreaterThan(0);
    });
  });

  describe('search functionality', () => {
    it('filters adaptors based on search query', async () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          adaptorsInUse={mockProjectAdaptors}
        />
      );

      const searchInput = screen.getByPlaceholderText(
        'Search for an adaptor to connect...'
      );
      fireEvent.change(searchInput, { target: { value: 'dhis' } });

      await waitFor(() => {
        expect(screen.getByText('Dhis2')).toBeInTheDocument();
        expect(screen.queryByText('Http')).not.toBeInTheDocument();
        expect(screen.queryByText('Salesforce')).not.toBeInTheDocument();
        expect(screen.queryByText('Common')).not.toBeInTheDocument();
      });
    });

    it('filters case-insensitively', async () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          adaptorsInUse={mockProjectAdaptors}
        />
      );

      const searchInput = screen.getByPlaceholderText(
        'Search for an adaptor to connect...'
      );
      fireEvent.change(searchInput, { target: { value: 'DHIS' } });

      await waitFor(() => {
        expect(screen.getByText('Dhis2')).toBeInTheDocument();
      });
    });

    it('shows empty state when no results match', async () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          adaptorsInUse={mockProjectAdaptors}
        />
      );

      const searchInput = screen.getByPlaceholderText(
        'Search for an adaptor to connect...'
      );
      fireEvent.change(searchInput, { target: { value: 'nonexistent' } });

      await waitFor(() => {
        expect(screen.getByText('No adaptor found')).toBeInTheDocument();
      });
    });

    it('resets search when modal closes and reopens', async () => {
      const mockContext = createMockStoreContext();

      const TestWrapper = ({ isOpen }: { isOpen: boolean }) => (
        <KeyboardProvider>
          <StoreContext.Provider value={mockContext as any}>
            <AdaptorSelectionModal
              isOpen={isOpen}
              onClose={onClose}
              onSelect={onSelect}
              adaptorsInUse={mockProjectAdaptors}
            />
          </StoreContext.Provider>
        </KeyboardProvider>
      );

      const { rerender } = render(<TestWrapper isOpen={true} />);

      // Search for something specific that filters out most adaptors
      const searchInput = screen.getByPlaceholderText(
        'Search for an adaptor to connect...'
      );
      fireEvent.change(searchInput, { target: { value: 'dhis' } });

      await waitFor(() => {
        expect(screen.queryByText('Http')).not.toBeInTheDocument();
        expect(screen.getByText('Dhis2')).toBeInTheDocument();
      });

      // Close modal
      rerender(<TestWrapper isOpen={false} />);

      // Reopen modal
      rerender(<TestWrapper isOpen={true} />);

      // Search should be cleared - all adaptors visible again
      await waitFor(() => {
        // Use getAllByText for duplicates
        expect(screen.getAllByText('Http').length).toBeGreaterThan(0);
        expect(screen.getByText('Dhis2')).toBeInTheDocument();
        expect(screen.getByText('Common')).toBeInTheDocument();
      });
    });
  });

  describe('immediate selection', () => {
    it('calls onSelect and onClose when adaptor clicked', () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          adaptorsInUse={mockProjectAdaptors}
        />
      );

      // Use getAllByText and pick first occurrence
      const httpRows = screen.getAllByText('Http');
      const httpRow = httpRows[0].closest('button');
      fireEvent.click(httpRow!);

      // Should immediately call onSelect with full adaptor spec and onClose
      expect(onSelect).toHaveBeenCalledWith('@openfn/language-http@1.0.0');
      expect(onClose).toHaveBeenCalled();
    });

    it('calls onSelect with correct adaptor name for different adaptors', () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          adaptorsInUse={mockProjectAdaptors}
        />
      );

      // Click salesforce adaptor
      const salesforceRows = screen.getAllByText('Salesforce');
      const salesforceRow = salesforceRows[0].closest('button');
      fireEvent.click(salesforceRow!);

      expect(onSelect).toHaveBeenCalledWith(
        '@openfn/language-salesforce@2.1.0'
      );
      expect(onClose).toHaveBeenCalled();
    });
  });
});
