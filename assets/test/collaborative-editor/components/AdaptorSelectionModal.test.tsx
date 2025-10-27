/**
 * Tests for AdaptorSelectionModal component
 *
 * Tests the modal that allows users to search and select adaptors
 * when creating new job nodes in the workflow canvas.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { AdaptorSelectionModal } from "../../../js/collaborative-editor/components/AdaptorSelectionModal";
import { StoreContext } from "../../../js/collaborative-editor/contexts/StoreProvider";
import { HotkeysProvider } from "react-hotkeys-hook";
import type { Adaptor } from "../../../js/collaborative-editor/types/adaptor";

// Mock useAdaptorIcons to avoid fetching icon manifest
vi.mock("#/workflow-diagram/useAdaptorIcons", () => ({
  default: () => null,
}));

// Mock adaptor data
const mockProjectAdaptors: Adaptor[] = [
  {
    name: "@openfn/language-http",
    latest: "1.0.0",
    versions: ["1.0.0", "0.9.0"],
  },
  {
    name: "@openfn/language-salesforce",
    latest: "2.1.0",
    versions: ["2.1.0", "2.0.0"],
  },
];

const mockAllAdaptors: Adaptor[] = [
  ...mockProjectAdaptors,
  {
    name: "@openfn/language-dhis2",
    latest: "3.2.1",
    versions: ["3.2.1", "3.2.0"],
  },
  {
    name: "@openfn/language-common",
    latest: "2.0.0",
    versions: ["2.0.0", "1.9.0"],
  },
];

// Mock store context with proper structure
function createMockStoreContext() {
  return {
    adaptorStore: {
      subscribe: vi.fn(() => vi.fn()),
      getSnapshot: vi.fn(() => ({
        adaptors: mockAllAdaptors,
        projectAdaptors: mockProjectAdaptors,
        isLoading: false,
        error: null,
      })),
      withSelector: vi.fn(
        selector => () =>
          selector({
            adaptors: mockAllAdaptors,
            projectAdaptors: mockProjectAdaptors,
            isLoading: false,
            error: null,
          })
      ),
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
    <HotkeysProvider>
      <StoreContext.Provider value={mockStoreContext as any}>
        {ui}
      </StoreContext.Provider>
    </HotkeysProvider>
  );
}

describe("AdaptorSelectionModal", () => {
  const onClose = vi.fn();
  const onSelect = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe("modal visibility", () => {
    it("renders when open", () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          projectAdaptors={mockProjectAdaptors}
        />
      );

      expect(screen.getByText("Select Adaptor")).toBeInTheDocument();
      expect(
        screen.getByPlaceholderText("Search adaptors...")
      ).toBeInTheDocument();
    });

    it("does not render when closed", () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={false}
          onClose={onClose}
          onSelect={onSelect}
        />
      );

      expect(screen.queryByText("Select Adaptor")).not.toBeInTheDocument();
    });
  });

  describe("adaptor display", () => {
    it("displays project adaptors section with adaptors", () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          projectAdaptors={mockProjectAdaptors}
        />
      );

      expect(screen.getByText("Project Adaptors")).toBeInTheDocument();
      // Use getAllByText since adaptors appear in both sections
      expect(screen.getAllByText("http").length).toBeGreaterThan(0);
      expect(screen.getAllByText("salesforce").length).toBeGreaterThan(0);
    });

    it("displays all adaptors section", () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          projectAdaptors={mockProjectAdaptors}
        />
      );

      expect(screen.getByText("All Adaptors")).toBeInTheDocument();
      expect(screen.getByText("dhis2")).toBeInTheDocument();
      expect(screen.getByText("common")).toBeInTheDocument();
    });

    it("shows 'Available Adaptors' when no project adaptors", () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          projectAdaptors={[]}
        />
      );

      expect(screen.queryByText("Project Adaptors")).not.toBeInTheDocument();
      expect(screen.getByText("Available Adaptors")).toBeInTheDocument();
    });

    it("displays adaptor version in description", () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          projectAdaptors={mockProjectAdaptors}
        />
      );

      // Use getAllByText since adaptors may appear in both project and all sections
      expect(screen.getAllByText("Latest: 1.0.0").length).toBeGreaterThan(0);
      expect(screen.getAllByText("Latest: 2.1.0").length).toBeGreaterThan(0);
    });
  });

  describe("search functionality", () => {
    it("filters adaptors based on search query", async () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          projectAdaptors={mockProjectAdaptors}
        />
      );

      const searchInput = screen.getByPlaceholderText("Search adaptors...");
      fireEvent.change(searchInput, { target: { value: "dhis" } });

      await waitFor(() => {
        expect(screen.getByText("dhis2")).toBeInTheDocument();
        expect(screen.queryByText("http")).not.toBeInTheDocument();
        expect(screen.queryByText("salesforce")).not.toBeInTheDocument();
        expect(screen.queryByText("common")).not.toBeInTheDocument();
      });
    });

    it("filters case-insensitively", async () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          projectAdaptors={mockProjectAdaptors}
        />
      );

      const searchInput = screen.getByPlaceholderText("Search adaptors...");
      fireEvent.change(searchInput, { target: { value: "DHIS" } });

      await waitFor(() => {
        expect(screen.getByText("dhis2")).toBeInTheDocument();
      });
    });

    it("shows empty state when no results match", async () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          projectAdaptors={mockProjectAdaptors}
        />
      );

      const searchInput = screen.getByPlaceholderText("Search adaptors...");
      fireEvent.change(searchInput, { target: { value: "nonexistent" } });

      await waitFor(() => {
        expect(
          screen.getByText("No adaptors match your search")
        ).toBeInTheDocument();
      });
    });

    it("resets search when modal closes and reopens", async () => {
      const mockContext = createMockStoreContext();

      const TestWrapper = ({ isOpen }: { isOpen: boolean }) => (
        <HotkeysProvider>
          <StoreContext.Provider value={mockContext as any}>
            <AdaptorSelectionModal
              isOpen={isOpen}
              onClose={onClose}
              onSelect={onSelect}
              projectAdaptors={mockProjectAdaptors}
            />
          </StoreContext.Provider>
        </HotkeysProvider>
      );

      const { rerender } = render(<TestWrapper isOpen={true} />);

      // Search for something specific that filters out most adaptors
      const searchInput = screen.getByPlaceholderText("Search adaptors...");
      fireEvent.change(searchInput, { target: { value: "dhis" } });

      await waitFor(() => {
        expect(screen.queryByText("http")).not.toBeInTheDocument();
        expect(screen.getByText("dhis2")).toBeInTheDocument();
      });

      // Close modal
      rerender(<TestWrapper isOpen={false} />);

      // Reopen modal
      rerender(<TestWrapper isOpen={true} />);

      // Search should be cleared - all adaptors visible again
      await waitFor(() => {
        // Use getAllByText for duplicates
        expect(screen.getAllByText("http").length).toBeGreaterThan(0);
        expect(screen.getByText("dhis2")).toBeInTheDocument();
        expect(screen.getByText("common")).toBeInTheDocument();
      });
    });
  });

  describe("adaptor selection", () => {
    it("selects adaptor when clicked", () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          projectAdaptors={mockProjectAdaptors}
        />
      );

      // Use getAllByText and pick first occurrence
      const httpRows = screen.getAllByText("http");
      const httpRow = httpRows[0].closest("button");
      fireEvent.click(httpRow!);

      // Continue button should be enabled
      const continueButton = screen.getByText("Continue");
      expect(continueButton).not.toBeDisabled();
    });

    it("changes selection when different adaptor clicked", () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          projectAdaptors={mockProjectAdaptors}
        />
      );

      // Click first adaptor - use getAllByText for duplicates
      const httpRows = screen.getAllByText("http");
      const httpRow = httpRows[0].closest("button");
      fireEvent.click(httpRow!);

      // Click second adaptor
      const salesforceRows = screen.getAllByText("salesforce");
      const salesforceRow = salesforceRows[0].closest("button");
      fireEvent.click(salesforceRow!);

      // Both clicks should work (selection state is internal)
      const continueButton = screen.getByText("Continue");
      expect(continueButton).not.toBeDisabled();
    });

    it("disables Continue button when no selection", () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          projectAdaptors={mockProjectAdaptors}
        />
      );

      const continueButton = screen.getByText("Continue");
      expect(continueButton).toBeDisabled();
    });
  });

  describe("modal actions", () => {
    it("calls onSelect and onClose when Continue clicked with selection", () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          projectAdaptors={mockProjectAdaptors}
        />
      );

      // Select adaptor - use getAllByText for duplicates
      const httpRows = screen.getAllByText("http");
      const httpRow = httpRows[0].closest("button");
      fireEvent.click(httpRow!);

      // Click Continue
      const continueButton = screen.getByText("Continue");
      fireEvent.click(continueButton);

      expect(onSelect).toHaveBeenCalledWith("@openfn/language-http");
      expect(onClose).toHaveBeenCalled();
    });

    it("calls onClose when Cancel clicked", () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          projectAdaptors={mockProjectAdaptors}
        />
      );

      const cancelButton = screen.getByText("Cancel");
      fireEvent.click(cancelButton);

      expect(onClose).toHaveBeenCalled();
      expect(onSelect).not.toHaveBeenCalled();
    });

    it("does not call onSelect when Continue clicked without selection", () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          projectAdaptors={mockProjectAdaptors}
        />
      );

      // Try to click Continue without selecting (button is disabled)
      const continueButton = screen.getByText("Continue");
      fireEvent.click(continueButton);

      // onSelect should not be called because button is disabled
      expect(onSelect).not.toHaveBeenCalled();
    });
  });

  describe("keyboard navigation", () => {
    it("confirms selection with Enter key when adaptor selected", () => {
      renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          projectAdaptors={mockProjectAdaptors}
        />
      );

      // Select adaptor - use getAllByText for duplicates
      const httpRows = screen.getAllByText("http");
      const httpRow = httpRows[0].closest("button");
      fireEvent.click(httpRow!);

      // Find the dialog panel by text content and fire keyDown on it
      const dialogTitle = screen.getByText("Select Adaptor");
      const dialogPanel = dialogTitle.closest("[data-headlessui-state]");

      if (dialogPanel) {
        fireEvent.keyDown(dialogPanel, { key: "Enter", code: "Enter" });
      }

      expect(onSelect).toHaveBeenCalledWith("@openfn/language-http");
      expect(onClose).toHaveBeenCalled();
    });

    it("does not confirm with Enter when no selection", () => {
      const { container } = renderWithProviders(
        <AdaptorSelectionModal
          isOpen={true}
          onClose={onClose}
          onSelect={onSelect}
          projectAdaptors={mockProjectAdaptors}
        />
      );

      // Press Enter without selecting
      const dialogPanel = container.querySelector('[role="dialog"]');
      if (dialogPanel) {
        fireEvent.keyDown(dialogPanel, { key: "Enter" });
      }

      expect(onSelect).not.toHaveBeenCalled();
    });
  });

  describe("state reset", () => {
    it("resets selection when modal closes", async () => {
      const mockContext = createMockStoreContext();

      const TestWrapper = ({ isOpen }: { isOpen: boolean }) => (
        <HotkeysProvider>
          <StoreContext.Provider value={mockContext as any}>
            <AdaptorSelectionModal
              isOpen={isOpen}
              onClose={onClose}
              onSelect={onSelect}
              projectAdaptors={mockProjectAdaptors}
            />
          </StoreContext.Provider>
        </HotkeysProvider>
      );

      const { rerender } = render(<TestWrapper isOpen={true} />);

      // Select adaptor - use getAllByText for duplicates
      const httpRows = screen.getAllByText("http");
      const httpRow = httpRows[0].closest("button");
      fireEvent.click(httpRow!);

      // Continue button enabled
      expect(screen.getByText("Continue")).not.toBeDisabled();

      // Close modal
      rerender(<TestWrapper isOpen={false} />);

      // Reopen modal
      rerender(<TestWrapper isOpen={true} />);

      // Continue button should be disabled (no selection)
      await waitFor(() => {
        expect(screen.getByText("Continue")).toBeDisabled();
      });
    });
  });
});
