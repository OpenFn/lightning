/**
 * ConfigureAdaptorModal Component Tests
 *
 * Tests the modal for configuring adaptor, version, and credential together.
 * This modal is opened from the JobForm "Connect" button (Phase 2R).
 *
 * Test coverage:
 * - Modal rendering with current adaptor/version/credential
 * - Adaptor change flow (opens nested AdaptorSelectionModal)
 * - Version selection dropdown
 * - Credential filtering by adaptor schema
 * - Radio button selection for credentials
 * - Save functionality
 * - Modal close behavior
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import {
  render,
  screen,
  fireEvent,
  waitFor,
  within,
} from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { HotkeysProvider } from "react-hotkeys-hook";

import { ConfigureAdaptorModal } from "../../../js/collaborative-editor/components/ConfigureAdaptorModal";
import { LiveViewActionsProvider } from "../../../js/collaborative-editor/contexts/LiveViewActionsContext";
import { StoreContext } from "../../../js/collaborative-editor/contexts/StoreProvider";
import type { Adaptor } from "../../../js/collaborative-editor/types/adaptor";
import type {
  ProjectCredential,
  KeychainCredential,
} from "../../../js/collaborative-editor/types/credential";

// Mock useAdaptorIcons to avoid fetching icon manifest
vi.mock("#/workflow-diagram/useAdaptorIcons", () => ({
  default: () => null,
}));

// Mock adaptor data
const mockProjectAdaptors: Adaptor[] = [
  {
    name: "@openfn/language-http",
    latest: "1.5.0",
    versions: [
      { version: "1.5.0" },
      { version: "1.0.0" },
      { version: "0.9.0" },
    ],
  },
  {
    name: "@openfn/language-salesforce",
    latest: "2.1.0",
    versions: [
      { version: "2.1.0" },
      { version: "2.0.0" },
      { version: "1.9.0" },
    ],
  },
  {
    name: "@openfn/language-common",
    latest: "2.0.0",
    versions: [{ version: "2.0.0" }],
  },
];

// Mock credential data
const mockProjectCredentials: ProjectCredential[] = [
  {
    id: "cred-1",
    project_credential_id: "proj-cred-1",
    name: "Salesforce Production",
    schema: "salesforce",
    external_id: "ext-1",
    inserted_at: "2024-01-01T00:00:00Z",
    updated_at: "2024-01-01T00:00:00Z",
    owner: { id: "user-1", name: "John Doe", email: "john@example.com" },
    oauth_client_name: null,
  },
  {
    id: "cred-2",
    project_credential_id: "proj-cred-2",
    name: "Salesforce Testing",
    schema: "salesforce",
    external_id: "ext-2",
    inserted_at: "2024-01-01T00:00:00Z",
    updated_at: "2024-01-01T00:00:00Z",
    owner: null,
    oauth_client_name: null,
  },
  {
    id: "cred-3",
    project_credential_id: "proj-cred-3",
    name: "HTTP API Key",
    schema: "http",
    external_id: "ext-3",
    inserted_at: "2024-01-01T00:00:00Z",
    updated_at: "2024-01-01T00:00:00Z",
    owner: null,
    oauth_client_name: null,
  },
  {
    id: "cred-4",
    project_credential_id: "proj-cred-4",
    name: "My Salesforce OAuth",
    schema: "oauth",
    oauth_client_name: "Salesforce Production Client",
    external_id: "ext-4",
    inserted_at: "2024-01-01T00:00:00Z",
    updated_at: "2024-01-01T00:00:00Z",
    owner: { id: "user-2", name: "Jane Smith", email: "jane@example.com" },
  },
];

const mockKeychainCredentials: KeychainCredential[] = [
  {
    id: "keychain-1",
    name: "Keychain Salesforce",
    path: "salesforce/production",
    default_credential_id: null,
    inserted_at: "2024-01-01T00:00:00Z",
    updated_at: "2024-01-01T00:00:00Z",
  },
];

// Mock store context
function createMockStoreContext() {
  const credentialSnapshot = {
    projectCredentials: mockProjectCredentials,
    keychainCredentials: mockKeychainCredentials,
    isLoading: false,
    error: null,
  };

  const adaptorSnapshot = {
    adaptors: mockProjectAdaptors,
    allAdaptors: mockProjectAdaptors,
    isLoading: false,
    error: null,
  };

  const awarenessSnapshot = { users: [] };
  const workflowSnapshot = { jobs: [] };
  const sessionSnapshot = { context: null };

  return {
    credentialStore: {
      subscribe: vi.fn(() => vi.fn()),
      getSnapshot: () => credentialSnapshot,
      withSelector: (selector: any) => {
        // Return a memoized function that always returns same reference
        const result = selector(credentialSnapshot);
        return () => result;
      },
    },
    adaptorStore: {
      subscribe: vi.fn(() => vi.fn()),
      getSnapshot: () => adaptorSnapshot,
      withSelector: (selector: any) => {
        const result = selector(adaptorSnapshot);
        return () => result;
      },
    },
    awarenessStore: {
      subscribe: vi.fn(() => vi.fn()),
      getSnapshot: () => awarenessSnapshot,
      withSelector: (selector: any) => {
        const result = selector(awarenessSnapshot);
        return () => result;
      },
    },
    workflowStore: {
      subscribe: vi.fn(() => vi.fn()),
      getSnapshot: () => workflowSnapshot,
      withSelector: (selector: any) => {
        const result = selector(workflowSnapshot);
        return () => result;
      },
    },
    sessionContextStore: {
      subscribe: vi.fn(() => vi.fn()),
      getSnapshot: () => sessionSnapshot,
      withSelector: (selector: any) => {
        const result = selector(sessionSnapshot);
        return () => result;
      },
    },
  };
}

// Create mock LiveView actions
const createMockLiveViewActions = () => ({
  pushEvent: vi.fn(),
  pushEventTo: vi.fn(),
  handleEvent: vi.fn(),
  navigate: vi.fn(),
});

function renderWithProviders(
  ui: React.ReactElement,
  mockStoreContext = createMockStoreContext(),
  mockLiveViewActions = createMockLiveViewActions()
) {
  return render(
    <HotkeysProvider>
      <StoreContext.Provider value={mockStoreContext as any}>
        <LiveViewActionsProvider actions={mockLiveViewActions}>
          {ui}
        </LiveViewActionsProvider>
      </StoreContext.Provider>
    </HotkeysProvider>
  );
}

describe("ConfigureAdaptorModal", () => {
  const mockOnClose = vi.fn();
  const mockOnSave = vi.fn();
  const mockOnOpenAdaptorPicker = vi.fn();
  const mockOnOpenCredentialModal = vi.fn();

  const defaultProps = {
    isOpen: true,
    onClose: mockOnClose,
    onSave: mockOnSave,
    onOpenAdaptorPicker: mockOnOpenAdaptorPicker,
    onOpenCredentialModal: mockOnOpenCredentialModal,
    currentAdaptor: "@openfn/language-salesforce",
    currentVersion: "2.1.0",
    currentCredentialId: null,
    allAdaptors: mockProjectAdaptors,
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe("Modal Rendering", () => {
    it("renders modal when open with title", () => {
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      expect(screen.getByText("Configure connection")).toBeInTheDocument();
    });

    it("does not render when closed", () => {
      renderWithProviders(
        <ConfigureAdaptorModal {...defaultProps} isOpen={false} />
      );

      expect(
        screen.queryByText("Configure connection")
      ).not.toBeInTheDocument();
    });

    it("renders close button", () => {
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      const closeButton = screen.getByRole("button", { name: /close/i });
      expect(closeButton).toBeInTheDocument();
    });

    it("closes modal when close button clicked", async () => {
      const user = userEvent.setup();
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      const closeButton = screen.getByRole("button", { name: /close/i });
      await user.click(closeButton);

      expect(mockOnClose).toHaveBeenCalledTimes(1);
    });
  });

  describe("Adaptor Section", () => {
    it("displays current adaptor with icon and display name", () => {
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      expect(screen.getByText("Adaptor")).toBeInTheDocument();
      expect(screen.getByText("Salesforce")).toBeInTheDocument();
    });

    it("displays Change button in adaptor section", () => {
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      // Get the Change button in adaptor section
      const adaptorSection = screen
        .getByText("Adaptor")
        .closest("div")!.parentElement!;
      const changeButton = within(adaptorSection).getByRole("button", {
        name: /change/i,
      });

      expect(changeButton).toBeInTheDocument();
    });

    it("calls onClose and onOpenAdaptorPicker when Change clicked", async () => {
      const user = userEvent.setup();
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      const adaptorSection = screen
        .getByText("Adaptor")
        .closest("div")!.parentElement!;
      const changeButton = within(adaptorSection).getByRole("button", {
        name: /change/i,
      });
      await user.click(changeButton);

      // Should close the modal and notify parent to open adaptor picker
      expect(mockOnClose).toHaveBeenCalledTimes(1);
      expect(mockOnOpenAdaptorPicker).toHaveBeenCalledTimes(1);
    });
  });

  describe("Version Section", () => {
    it("displays version dropdown with current version", () => {
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      expect(screen.getByText("Version")).toBeInTheDocument();

      const versionSelect = screen.getByDisplayValue("2.1.0");
      expect(versionSelect).toBeInTheDocument();
    });

    it("displays all version options for selected adaptor", async () => {
      const user = userEvent.setup();
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      const versionInput = screen.getByDisplayValue("2.1.0");

      // Click to open the combobox options
      await user.click(versionInput);

      // Wait for options to appear
      const options = await screen.findAllByRole("option");

      // Should have 4 versions: "latest" + 3 versions from mock data
      expect(options.length).toBe(4);
      expect(options[0]).toHaveTextContent("latest");
      expect(options[1]).toHaveTextContent("2.1.0");
      expect(options[2]).toHaveTextContent("2.0.0");
      expect(options[3]).toHaveTextContent("1.9.0");
    });

    it("updates version when dropdown selection changes", async () => {
      const user = userEvent.setup();
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      const versionInput = screen.getByDisplayValue("2.1.0");

      // Click to open the combobox
      await user.click(versionInput);

      // Wait for options and click on version 2.0.0
      const options = await screen.findAllByRole("option");
      const option200 = options.find(opt => opt.textContent === "2.0.0");
      expect(option200).toBeDefined();
      await user.click(option200!);

      // Wait for dropdown to close
      await waitFor(() => {
        expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
      });

      // Check the input now shows 2.0.0
      expect(screen.getByDisplayValue("2.0.0")).toBeInTheDocument();
    });

    it("sorts versions semantically (not alphabetically)", async () => {
      const user = userEvent.setup();
      // Create adaptor with versions that need semantic sorting
      const adaptorWithManyVersions: Adaptor = {
        name: "@openfn/language-test",
        latest: "10.0.0",
        versions: [
          { version: "2.0.0" },
          { version: "10.0.0" },
          { version: "1.9.0" },
          { version: "9.0.0" },
          { version: "1.10.0" },
        ],
        repo: "https://github.com/openfn/language-test",
      };

      renderWithProviders(
        <ConfigureAdaptorModal
          {...defaultProps}
          currentAdaptor="@openfn/language-test"
          allAdaptors={[adaptorWithManyVersions]}
        />
      );

      const versionInput = screen.getByRole("combobox", { name: /version/i });

      // Click to open the combobox
      await user.click(versionInput);

      // Wait for options to appear
      const options = await screen.findAllByRole("option");

      // Should be sorted: "latest" first, then 10.0.0, 9.0.0, 2.0.0, 1.10.0, 1.9.0
      expect(options[0]).toHaveTextContent("latest");
      expect(options[1]).toHaveTextContent("10.0.0");
      expect(options[2]).toHaveTextContent("9.0.0");
      expect(options[3]).toHaveTextContent("2.0.0");
      expect(options[4]).toHaveTextContent("1.10.0");
      expect(options[5]).toHaveTextContent("1.9.0");
    });
  });

  describe("Credential Filtering", () => {
    it("filters credentials by adaptor schema (Salesforce)", () => {
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      // Should show only Salesforce credentials (schema-matched)
      expect(screen.getByText("Salesforce Production")).toBeInTheDocument();
      expect(screen.getByText("Salesforce Testing")).toBeInTheDocument();

      // Should NOT show HTTP credential in main modal (moved to "See more" modal)
      expect(screen.queryByText("HTTP API Key")).not.toBeInTheDocument();

      // Should NOT show keychain credential in main modal (moved to "See more" modal)
      expect(screen.queryByText("Keychain Salesforce")).not.toBeInTheDocument();

      // Should show "Other credentials" link
      expect(screen.getByText(/other credentials/i)).toBeInTheDocument();
    });

    it("filters credentials when adaptor changes", async () => {
      const user = userEvent.setup();
      renderWithProviders(
        <ConfigureAdaptorModal
          {...defaultProps}
          currentAdaptor="@openfn/language-http"
        />
      );

      // Should show HTTP credential in schema-matched section (since it's http adaptor)
      expect(screen.getByText("HTTP API Key")).toBeInTheDocument();

      // Should NOT show Salesforce project credentials (no match)
      expect(
        screen.queryByText("Salesforce Production")
      ).not.toBeInTheDocument();

      // Should NOT show keychain credentials in main modal (moved to "See more" modal)
      expect(screen.queryByText("Keychain Salesforce")).not.toBeInTheDocument();

      // Should show "Other credentials" link
      expect(screen.getByText(/other credentials/i)).toBeInTheDocument();
    });

    it("matches OAuth credentials by oauth_client_name containing adaptor name", () => {
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      // Should show both Salesforce schema credentials AND OAuth credential with "Salesforce" in oauth_client_name
      expect(screen.getByText("Salesforce Production")).toBeInTheDocument();
      expect(screen.getByText("Salesforce Testing")).toBeInTheDocument();
      expect(screen.getByText("My Salesforce OAuth")).toBeInTheDocument();

      // Should show 3 radio buttons (2 schema-matched + 1 OAuth matched)
      const radioButtons = screen.getAllByRole("radio");
      expect(radioButtons.length).toBe(3);

      // Should NOT show HTTP or keychain in main view
      expect(screen.queryByText("HTTP API Key")).not.toBeInTheDocument();
      expect(screen.queryByText("Keychain Salesforce")).not.toBeInTheDocument();
    });

    it("smart OAuth matching handles spaces and hyphens", () => {
      // Test Google Drive OAuth client matching "googledrive" adaptor
      const googleDriveCredential = {
        id: "cred-google",
        project_credential_id: "proj-cred-google",
        name: "My Google Drive OAuth",
        schema: "oauth",
        oauth_client_name: "Google Drive Production", // Note the space
        external_id: "ext-google",
        inserted_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
      };

      const credSnapshot = {
        projectCredentials: [googleDriveCredential],
        keychainCredentials: [],
        isLoading: false,
        error: null,
      };

      const adaptorSnapshot = {
        adaptors: mockProjectAdaptors,
        allAdaptors: mockProjectAdaptors,
        isLoading: false,
        error: null,
      };

      const storeContext = {
        credentialStore: {
          subscribe: vi.fn(() => vi.fn()),
          getSnapshot: () => credSnapshot,
          withSelector: (selector: any) => {
            const result = selector(credSnapshot);
            return () => result;
          },
        },
        adaptorStore: {
          subscribe: vi.fn(() => vi.fn()),
          getSnapshot: () => adaptorSnapshot,
          withSelector: (selector: any) => {
            const result = selector(adaptorSnapshot);
            return () => result;
          },
        },
        awarenessStore: {
          subscribe: vi.fn(() => vi.fn()),
          getSnapshot: () => ({ users: [] }),
          withSelector: (selector: any) => () => selector({ users: [] }),
        },
        workflowStore: {
          subscribe: vi.fn(() => vi.fn()),
          getSnapshot: () => ({ jobs: [] }),
          withSelector: (selector: any) => () => selector({ jobs: [] }),
        },
        sessionContextStore: {
          subscribe: vi.fn(() => vi.fn()),
          getSnapshot: () => ({ context: null }),
          withSelector: (selector: any) => () => selector({ context: null }),
        },
      };

      renderWithProviders(
        <ConfigureAdaptorModal
          {...defaultProps}
          currentAdaptor="@openfn/language-googledrive" // No space
        />,
        storeContext as any
      );

      // Should match "Google Drive" client to "googledrive" adaptor
      expect(screen.getByText("My Google Drive OAuth")).toBeInTheDocument();
    });

    it("smart OAuth matching handles hyphens and underscores", () => {
      // Test Google Sheets OAuth client with hyphen matching "googlesheets" adaptor
      const googleSheetsCredential = {
        id: "cred-sheets",
        project_credential_id: "proj-cred-sheets",
        name: "My Google Sheets OAuth",
        schema: "oauth",
        oauth_client_name: "Google-Sheets_Client", // Hyphen and underscore
        external_id: "ext-sheets",
        inserted_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
      };

      const credSnapshot = {
        projectCredentials: [googleSheetsCredential],
        keychainCredentials: [],
        isLoading: false,
        error: null,
      };

      const adaptorSnapshot = {
        adaptors: mockProjectAdaptors,
        allAdaptors: mockProjectAdaptors,
        isLoading: false,
        error: null,
      };

      const storeContext = {
        credentialStore: {
          subscribe: vi.fn(() => vi.fn()),
          getSnapshot: () => credSnapshot,
          withSelector: (selector: any) => {
            const result = selector(credSnapshot);
            return () => result;
          },
        },
        adaptorStore: {
          subscribe: vi.fn(() => vi.fn()),
          getSnapshot: () => adaptorSnapshot,
          withSelector: (selector: any) => {
            const result = selector(adaptorSnapshot);
            return () => result;
          },
        },
        awarenessStore: {
          subscribe: vi.fn(() => vi.fn()),
          getSnapshot: () => ({ users: [] }),
          withSelector: (selector: any) => () => selector({ users: [] }),
        },
        workflowStore: {
          subscribe: vi.fn(() => vi.fn()),
          getSnapshot: () => ({ jobs: [] }),
          withSelector: (selector: any) => () => selector({ jobs: [] }),
        },
        sessionContextStore: {
          subscribe: vi.fn(() => vi.fn()),
          getSnapshot: () => ({ context: null }),
          withSelector: (selector: any) => () => selector({ context: null }),
        },
      };

      renderWithProviders(
        <ConfigureAdaptorModal
          {...defaultProps}
          currentAdaptor="@openfn/language-googlesheets"
        />,
        storeContext as any
      );

      // Should match "Google-Sheets_Client" to "googlesheets"
      expect(screen.getByText("My Google Sheets OAuth")).toBeInTheDocument();
    });

    it("shows informative message for adaptors that don't need credentials", () => {
      renderWithProviders(
        <ConfigureAdaptorModal
          {...defaultProps}
          currentAdaptor="@openfn/language-common"
        />
      );

      // Should show message that adaptor doesn't need credentials
      expect(
        screen.getByText("This adaptor does not require credentials.")
      ).toBeInTheDocument();

      // Should NOT show credential list or New Credential button
      expect(screen.queryByText("HTTP API Key")).not.toBeInTheDocument();
      expect(screen.queryByText("Keychain Salesforce")).not.toBeInTheDocument();
      expect(
        screen.queryByText("Salesforce Production")
      ).not.toBeInTheDocument();

      // New Credential button should be hidden
      expect(
        screen.queryByRole("button", { name: /new credential/i })
      ).not.toBeInTheDocument();

      // Should NOT show "Back to matching credentials" link (no matching credentials to go back to)
      expect(
        screen.queryByText(/back to matching credentials/i)
      ).not.toBeInTheDocument();
    });

    it("allows manual toggle between matching and other credentials", async () => {
      const user = userEvent.setup();
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      // Initially shows schema-matched credentials (Salesforce)
      expect(screen.getByText("Salesforce Production")).toBeInTheDocument();
      expect(screen.queryByText("HTTP API Key")).not.toBeInTheDocument();
      expect(screen.queryByText("Keychain Salesforce")).not.toBeInTheDocument();

      // Click "Other credentials" link
      const otherCredentialsLink = screen.getByText(/other credentials/i);
      await user.click(otherCredentialsLink);

      // Now shows other credentials (HTTP and Keychain)
      expect(screen.getByText("HTTP API Key")).toBeInTheDocument();
      expect(screen.getByText("Keychain Salesforce")).toBeInTheDocument();
      expect(
        screen.queryByText("Salesforce Production")
      ).not.toBeInTheDocument();

      // Click "Back to matching credentials" link
      const backLink = screen.getByText(/back to matching credentials/i);
      await user.click(backLink);

      // Back to schema-matched credentials
      expect(screen.getByText("Salesforce Production")).toBeInTheDocument();
      expect(screen.queryByText("HTTP API Key")).not.toBeInTheDocument();
      expect(screen.queryByText("Keychain Salesforce")).not.toBeInTheDocument();
    });

    it("shows empty state when no credentials exist at all", () => {
      // Create a mock store context with no credentials
      const emptyCredentialSnapshot = {
        projectCredentials: [],
        keychainCredentials: [],
        isLoading: false,
        error: null,
      };

      const adaptorSnapshot = {
        adaptors: mockProjectAdaptors,
        allAdaptors: mockProjectAdaptors,
        isLoading: false,
        error: null,
      };

      const emptyStoreContext = {
        credentialStore: {
          subscribe: vi.fn(() => vi.fn()),
          getSnapshot: () => emptyCredentialSnapshot,
          withSelector: (selector: any) => {
            const result = selector(emptyCredentialSnapshot);
            return () => result;
          },
        },
        adaptorStore: {
          subscribe: vi.fn(() => vi.fn()),
          getSnapshot: () => adaptorSnapshot,
          withSelector: (selector: any) => {
            const result = selector(adaptorSnapshot);
            return () => result;
          },
        },
        awarenessStore: {
          subscribe: vi.fn(() => vi.fn()),
          getSnapshot: () => ({ users: [] }),
          withSelector: (selector: any) => {
            const result = selector({ users: [] });
            return () => result;
          },
        },
        workflowStore: {
          subscribe: vi.fn(() => vi.fn()),
          getSnapshot: () => ({ jobs: [] }),
          withSelector: (selector: any) => {
            const result = selector({ jobs: [] });
            return () => result;
          },
        },
        sessionContextStore: {
          subscribe: vi.fn(() => vi.fn()),
          getSnapshot: () => ({ context: null }),
          withSelector: (selector: any) => {
            const result = selector({ context: null });
            return () => result;
          },
        },
      };

      renderWithProviders(
        <ConfigureAdaptorModal {...defaultProps} />,
        emptyStoreContext as any
      );

      // Should show empty state message
      expect(
        screen.getByText(/no credentials found in this project/i)
      ).toBeInTheDocument();

      // Should show create credential button
      expect(screen.getByText(/create a new credential/i)).toBeInTheDocument();

      // Should NOT show any credential lists or toggle links
      expect(screen.queryByText(/other credentials/i)).not.toBeInTheDocument();
      expect(
        screen.queryByText(/back to matching credentials/i)
      ).not.toBeInTheDocument();
    });
  });

  describe("Credential Selection", () => {
    it("displays credentials as radio buttons", () => {
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      const radioButtons = screen.getAllByRole("radio");

      // 3 credentials shown: 2 schema-matched Salesforce + 1 OAuth with Salesforce client
      // (HTTP and keychain are in "Other credentials" view)
      expect(radioButtons.length).toBe(3);
    });

    it("displays credential metadata (owner)", () => {
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      expect(screen.getByText("John Doe")).toBeInTheDocument();
    });

    it("selects credential when radio button clicked", async () => {
      const user = userEvent.setup();
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      const productionRadio = screen
        .getByText("Salesforce Production")
        .closest("label")!
        .querySelector('input[type="radio"]') as HTMLInputElement;

      await user.click(productionRadio);

      expect(productionRadio.checked).toBe(true);
    });

    it("shows current credential as selected", () => {
      renderWithProviders(
        <ConfigureAdaptorModal
          {...defaultProps}
          currentCredentialId="proj-cred-1"
        />
      );

      const productionRadio = screen
        .getByText("Salesforce Production")
        .closest("label")!
        .querySelector('input[type="radio"]') as HTMLInputElement;

      expect(productionRadio.checked).toBe(true);
    });

    it("allows changing credential selection", async () => {
      const user = userEvent.setup();
      renderWithProviders(
        <ConfigureAdaptorModal
          {...defaultProps}
          currentCredentialId="proj-cred-1"
        />
      );

      // Initially selected
      const productionRadio = screen
        .getByText("Salesforce Production")
        .closest("label")!
        .querySelector('input[type="radio"]') as HTMLInputElement;
      expect(productionRadio.checked).toBe(true);

      // Click different credential
      const testingRadio = screen
        .getByText("Salesforce Testing")
        .closest("label")!
        .querySelector('input[type="radio"]') as HTMLInputElement;
      await user.click(testingRadio);

      // Selection should change
      expect(productionRadio.checked).toBe(false);
      expect(testingRadio.checked).toBe(true);
    });
  });

  describe("Adaptor Change Flow", () => {
    it("updates internal state when reopened with new adaptor", () => {
      const mockLiveViewActions = createMockLiveViewActions();
      const mockStoreContext = createMockStoreContext();

      // Start with Salesforce
      const { rerender } = renderWithProviders(
        <ConfigureAdaptorModal
          {...defaultProps}
          currentAdaptor="@openfn/language-salesforce"
          currentCredentialId="proj-cred-1"
        />,
        mockStoreContext,
        mockLiveViewActions
      );

      // Verify Salesforce is shown
      expect(screen.getByText("Salesforce")).toBeInTheDocument();

      // Close modal (simulating user clicking Change button)
      rerender(
        <HotkeysProvider>
          <StoreContext.Provider value={mockStoreContext as any}>
            <LiveViewActionsProvider actions={mockLiveViewActions}>
              <ConfigureAdaptorModal
                {...defaultProps}
                isOpen={false} // Modal closed
                currentAdaptor="@openfn/language-salesforce"
              />
            </LiveViewActionsProvider>
          </StoreContext.Provider>
        </HotkeysProvider>
      );

      // Reopen with new adaptor (simulating selection from AdaptorSelectionModal)
      rerender(
        <HotkeysProvider>
          <StoreContext.Provider value={mockStoreContext as any}>
            <LiveViewActionsProvider actions={mockLiveViewActions}>
              <ConfigureAdaptorModal
                {...defaultProps}
                isOpen={true}
                currentAdaptor="@openfn/language-http"
                currentVersion="1.5.0" // Parent updates version for new adaptor
                currentCredentialId={null} // Credential cleared
              />
            </LiveViewActionsProvider>
          </StoreContext.Provider>
        </HotkeysProvider>
      );

      // Should show HTTP adaptor now
      expect(screen.getByText("Http")).toBeInTheDocument();

      // Version should be set to the currentVersion prop (1.5.0)
      const versionInput = screen.getByRole("combobox", {
        name: /version/i,
      }) as HTMLInputElement;
      expect(versionInput.value).toBe("1.5.0");
    });
  });

  describe("Save Functionality", () => {
    it("calls onSave with correct config when Save clicked", async () => {
      const user = userEvent.setup();
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      // Select a credential
      const productionRadio = screen
        .getByText("Salesforce Production")
        .closest("label")!
        .querySelector('input[type="radio"]') as HTMLInputElement;
      await user.click(productionRadio);

      // Click Save
      const saveButton = screen.getByRole("button", { name: /save/i });
      await user.click(saveButton);

      expect(mockOnSave).toHaveBeenCalledWith({
        adaptorPackage: "@openfn/language-salesforce",
        adaptorVersion: "2.1.0",
        credentialId: "proj-cred-1",
      });
    });

    it("calls onSave with null credentialId when none selected", async () => {
      const user = userEvent.setup();
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      // Don't select any credential
      const saveButton = screen.getByRole("button", { name: /save/i });
      await user.click(saveButton);

      expect(mockOnSave).toHaveBeenCalledWith({
        adaptorPackage: "@openfn/language-salesforce",
        adaptorVersion: "2.1.0",
        credentialId: null,
      });
    });

    it("closes modal after save", async () => {
      const user = userEvent.setup();
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      const saveButton = screen.getByRole("button", { name: /save/i });
      await user.click(saveButton);

      expect(mockOnClose).toHaveBeenCalledTimes(1);
    });

    it("saves with new adaptor after parent switches it", async () => {
      const user = userEvent.setup();
      const mockLiveViewActions = createMockLiveViewActions();
      const mockStoreContext = createMockStoreContext();

      // Render with Salesforce initially
      const { rerender } = renderWithProviders(
        <ConfigureAdaptorModal
          {...defaultProps}
          currentAdaptor="@openfn/language-salesforce"
        />,
        mockStoreContext,
        mockLiveViewActions
      );

      // Close modal (simulating: Close → Adaptor Picker)
      rerender(
        <HotkeysProvider>
          <StoreContext.Provider value={mockStoreContext as any}>
            <LiveViewActionsProvider actions={mockLiveViewActions}>
              <ConfigureAdaptorModal
                {...defaultProps}
                isOpen={false}
                currentAdaptor="@openfn/language-salesforce"
              />
            </LiveViewActionsProvider>
          </StoreContext.Provider>
        </HotkeysProvider>
      );

      // Reopen with HTTP (simulating: Adaptor Picker → Reopen)
      rerender(
        <HotkeysProvider>
          <StoreContext.Provider value={mockStoreContext as any}>
            <LiveViewActionsProvider actions={mockLiveViewActions}>
              <ConfigureAdaptorModal
                {...defaultProps}
                isOpen={true}
                currentAdaptor="@openfn/language-http"
                currentVersion="1.5.0" // Parent updates version for new adaptor
              />
            </LiveViewActionsProvider>
          </StoreContext.Provider>
        </HotkeysProvider>
      );

      // Verify HTTP is shown
      expect(screen.getByText("Http")).toBeInTheDocument();

      // Click Save
      const saveButton = screen.getByRole("button", { name: /save/i });
      await user.click(saveButton);

      expect(mockOnSave).toHaveBeenCalledWith({
        adaptorPackage: "@openfn/language-http",
        adaptorVersion: "1.5.0", // Newest version, not "latest"
        credentialId: null,
      });
    });

    it("includes changed version in save", async () => {
      const user = userEvent.setup();
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      // Change version
      const versionInput = screen.getByDisplayValue("2.1.0");
      await user.click(versionInput);

      // Wait for and select version 2.0.0
      const options = await screen.findAllByRole("option");
      const option200 = options.find(opt => opt.textContent === "2.0.0");
      expect(option200).toBeDefined();
      await user.click(option200!);

      // Wait for dropdown to close and state to update
      await waitFor(() => {
        expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
      });

      // Save
      const saveButton = screen.getByRole("button", { name: /save/i });
      await user.click(saveButton);

      expect(mockOnSave).toHaveBeenCalledWith({
        adaptorPackage: "@openfn/language-salesforce",
        adaptorVersion: "2.0.0",
        credentialId: null,
      });
    });
  });

  describe("Modal State Reset", () => {
    it("resets to current values when modal reopens", () => {
      const mockLiveViewActions = createMockLiveViewActions();
      const mockStoreContext = createMockStoreContext();

      const { rerender } = renderWithProviders(
        <ConfigureAdaptorModal {...defaultProps} isOpen={true} />,
        mockStoreContext,
        mockLiveViewActions
      );

      // Close modal
      rerender(
        <HotkeysProvider>
          <StoreContext.Provider value={mockStoreContext as any}>
            <LiveViewActionsProvider actions={mockLiveViewActions}>
              <ConfigureAdaptorModal {...defaultProps} isOpen={false} />
            </LiveViewActionsProvider>
          </StoreContext.Provider>
        </HotkeysProvider>
      );

      // Reopen modal
      rerender(
        <HotkeysProvider>
          <StoreContext.Provider value={mockStoreContext as any}>
            <LiveViewActionsProvider actions={mockLiveViewActions}>
              <ConfigureAdaptorModal {...defaultProps} isOpen={true} />
            </LiveViewActionsProvider>
          </StoreContext.Provider>
        </HotkeysProvider>
      );

      // Should reset to initial values
      expect(screen.getByText("Salesforce")).toBeInTheDocument();
      expect(screen.getByDisplayValue("2.1.0")).toBeInTheDocument();
    });
  });

  describe("Accessibility", () => {
    it("has proper aria-label on version dropdown", () => {
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      const versionInput = screen.getByRole("combobox", { name: /version/i });
      expect(versionInput).toBeInTheDocument();
    });

    it("has proper labels for radio buttons", () => {
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      const radioButtons = screen.getAllByRole("radio");
      radioButtons.forEach(radio => {
        expect(radio.closest("label")).toBeInTheDocument();
      });
    });

    it("has dialog role on modal", () => {
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      const dialog = screen.getByRole("dialog");
      expect(dialog).toBeInTheDocument();
    });
  });

  describe("New Credential Link", () => {
    it("displays New Credential link", () => {
      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      const newCredLink = screen.getByRole("button", {
        name: /new credential/i,
      });
      expect(newCredLink).toBeInTheDocument();
    });

    it("calls onOpenCredentialModal when New Credential clicked", async () => {
      const user = userEvent.setup();

      renderWithProviders(<ConfigureAdaptorModal {...defaultProps} />);

      const newCredLink = screen.getByRole("button", {
        name: /new credential/i,
      });
      await user.click(newCredLink);

      expect(mockOnOpenCredentialModal).toHaveBeenCalledWith("salesforce");
    });
  });
});
