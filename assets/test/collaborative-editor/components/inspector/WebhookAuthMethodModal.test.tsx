import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

import { WebhookAuthMethodModal } from "../../../../js/collaborative-editor/components/inspector/WebhookAuthMethodModal";
import type { WebhookAuthMethod } from "../../../../js/collaborative-editor/types/sessionContext";
import type { Workflow } from "../../../../js/collaborative-editor/types/workflow";
import { LiveViewActionsProvider } from "../../../../js/collaborative-editor/contexts/LiveViewActionsContext";

describe("WebhookAuthMethodModal", () => {
  const mockTrigger = {
    id: "trigger-1",
    type: "webhook" as const,
    enabled: true,
    webhook_auth_methods: [],
  } as Workflow.Trigger;

  const mockAuthMethods: WebhookAuthMethod[] = [
    {
      id: "auth-1",
      name: "API Key Auth",
      auth_type: "api",
    },
    {
      id: "auth-2",
      name: "Basic Auth",
      auth_type: "basic",
    },
  ];

  const mockOnClose = vi.fn();
  const mockOnSave = vi.fn();
  const mockPushEvent = vi.fn();

  const defaultProps = {
    trigger: mockTrigger,
    projectAuthMethods: mockAuthMethods,
    projectId: "project-1",
    onClose: mockOnClose,
    onSave: mockOnSave,
  };

  beforeEach(() => {
    vi.clearAllMocks();
    mockOnSave.mockResolvedValue(undefined);
  });

  function renderModal(
    props: Partial<typeof defaultProps> = {},
    liveViewActions = {
      pushEvent: mockPushEvent,
      handleEvent: vi.fn(),
      actions: {},
    }
  ) {
    return render(
      <LiveViewActionsProvider {...liveViewActions}>
        <WebhookAuthMethodModal {...defaultProps} {...props} />
      </LiveViewActionsProvider>
    );
  }

  describe("rendering", () => {
    it("renders modal with title and description", () => {
      renderModal();

      expect(
        screen.getByText("Webhook Authentication Methods")
      ).toBeInTheDocument();
      expect(
        screen.getByText(
          "Select which authentication methods apply to this webhook trigger"
        )
      ).toBeInTheDocument();
    });

    it("renders close button", () => {
      renderModal();

      const closeButtons = screen.getAllByRole("button", { name: /close/i });
      expect(closeButtons.length).toBeGreaterThan(0);
    });

    it("renders all available auth methods", () => {
      renderModal();

      expect(screen.getByText("API Key Auth")).toBeInTheDocument();
      expect(screen.getByText("Basic Auth")).toBeInTheDocument();
      expect(screen.getByText("API Key")).toBeInTheDocument();
      expect(screen.getByText("Basic Authentication")).toBeInTheDocument();
    });

    it("shows selected count in footer", () => {
      renderModal();

      expect(screen.getByText("0 methods selected")).toBeInTheDocument();
    });

    it("renders save and cancel buttons", () => {
      renderModal();

      expect(screen.getByRole("button", { name: /save/i })).toBeInTheDocument();
      expect(
        screen.getByRole("button", { name: /cancel/i })
      ).toBeInTheDocument();
    });
  });

  describe("empty state", () => {
    it("shows empty state when no auth methods available", () => {
      renderModal({ projectAuthMethods: [] });

      expect(
        screen.getByText("No webhook authentication methods available.")
      ).toBeInTheDocument();
      expect(
        screen.getByRole("button", {
          name: /create a new authentication method/i,
        })
      ).toBeInTheDocument();
    });

    it("has button to create new auth method from empty state", () => {
      renderModal({ projectAuthMethods: [] });

      const createButton = screen.getByRole("button", {
        name: /create a new authentication method/i,
      });
      expect(createButton).toBeInTheDocument();
      expect(createButton).not.toBeDisabled();
    });

    it("disables save button when no methods available", () => {
      renderModal({ projectAuthMethods: [] });

      const saveButton = screen.getByRole("button", { name: /save/i });
      expect(saveButton).toBeDisabled();
    });
  });

  describe("selection behavior", () => {
    it("initializes checkboxes based on trigger's current associations", () => {
      const triggerWithAuth = {
        ...mockTrigger,
        webhook_auth_methods: [mockAuthMethods[0]],
      } as Workflow.Trigger;

      renderModal({ trigger: triggerWithAuth });

      const checkboxes = screen.getAllByRole("checkbox");
      expect(checkboxes[0]).toBeChecked();
      expect(checkboxes[1]).not.toBeChecked();
    });

    it("toggles checkbox when clicked", async () => {
      const user = userEvent.setup();
      renderModal();

      const checkboxes = screen.getAllByRole("checkbox");
      expect(checkboxes[0]).not.toBeChecked();

      await user.click(checkboxes[0]);
      expect(checkboxes[0]).toBeChecked();

      await user.click(checkboxes[0]);
      expect(checkboxes[0]).not.toBeChecked();
    });

    it("updates selected count when toggling selections", async () => {
      const user = userEvent.setup();
      renderModal();

      expect(screen.getByText("0 methods selected")).toBeInTheDocument();

      const checkboxes = screen.getAllByRole("checkbox");
      await user.click(checkboxes[0]);

      expect(screen.getByText("1 method selected")).toBeInTheDocument();

      await user.click(checkboxes[1]);

      expect(screen.getByText("2 methods selected")).toBeInTheDocument();
    });

    it("shows visual feedback for selected items", async () => {
      const user = userEvent.setup();
      renderModal();

      const checkboxes = screen.getAllByRole("checkbox");
      const label = checkboxes[0].closest("label");

      await user.click(checkboxes[0]);

      expect(label).toHaveClass("border-indigo-300", "bg-indigo-50");
    });

    it("toggles selection when clicking label", async () => {
      const user = userEvent.setup();
      renderModal();

      const label = screen.getByText("API Key Auth").closest("label");
      expect(label).toBeInTheDocument();

      const checkbox = screen.getAllByRole("checkbox")[0];
      expect(checkbox).not.toBeChecked();

      await user.click(label!);
      expect(checkbox).toBeChecked();
    });
  });

  describe("save functionality", () => {
    it("calls onSave with selected method IDs", async () => {
      const user = userEvent.setup();
      renderModal();

      const checkboxes = screen.getAllByRole("checkbox");
      await user.click(checkboxes[0]);
      await user.click(checkboxes[1]);

      const saveButton = screen.getByRole("button", { name: /save/i });
      await user.click(saveButton);

      await waitFor(() => {
        expect(mockOnSave).toHaveBeenCalledWith(["auth-1", "auth-2"]);
      });
    });

    it("calls onClose after successful save", async () => {
      const user = userEvent.setup();
      renderModal();

      const checkboxes = screen.getAllByRole("checkbox");
      await user.click(checkboxes[0]);

      const saveButton = screen.getByRole("button", { name: /save/i });
      await user.click(saveButton);

      await waitFor(() => {
        expect(mockOnClose).toHaveBeenCalled();
      });
    });

    it("shows saving state during save operation", async () => {
      const user = userEvent.setup();
      let resolveOnSave: () => void;
      const delayedOnSave = vi.fn(
        () =>
          new Promise<void>(resolve => {
            resolveOnSave = resolve;
          })
      );

      renderModal({ onSave: delayedOnSave });

      const checkboxes = screen.getAllByRole("checkbox");
      await user.click(checkboxes[0]);

      const saveButton = screen.getByRole("button", { name: /save/i });
      await user.click(saveButton);

      expect(screen.getByText("Saving...")).toBeInTheDocument();
      expect(saveButton).toBeDisabled();

      resolveOnSave!();
      await waitFor(() => {
        expect(mockOnClose).not.toHaveBeenCalled();
      });
    });

    it("displays error message when save fails", async () => {
      const user = userEvent.setup();
      const errorOnSave = vi.fn().mockRejectedValue(new Error("Network error"));

      renderModal({ onSave: errorOnSave });

      const checkboxes = screen.getAllByRole("checkbox");
      await user.click(checkboxes[0]);

      const saveButton = screen.getByRole("button", { name: /save/i });
      await user.click(saveButton);

      await waitFor(() => {
        expect(screen.getByText("Network error")).toBeInTheDocument();
      });

      expect(mockOnClose).not.toHaveBeenCalled();
    });

    it("handles non-Error exceptions in save", async () => {
      const user = userEvent.setup();
      const errorOnSave = vi.fn().mockRejectedValue("String error");

      renderModal({ onSave: errorOnSave });

      const checkboxes = screen.getAllByRole("checkbox");
      await user.click(checkboxes[0]);

      const saveButton = screen.getByRole("button", { name: /save/i });
      await user.click(saveButton);

      await waitFor(() => {
        expect(screen.getByText("Failed to save")).toBeInTheDocument();
      });
    });

    it("can save with no selections (clear all)", async () => {
      const user = userEvent.setup();
      const triggerWithAuth = {
        ...mockTrigger,
        webhook_auth_methods: [mockAuthMethods[0]],
      } as Workflow.Trigger;

      renderModal({ trigger: triggerWithAuth });

      // Uncheck the already checked checkbox
      const checkboxes = screen.getAllByRole("checkbox");
      await user.click(checkboxes[0]);

      const saveButton = screen.getByRole("button", { name: /save/i });
      await user.click(saveButton);

      await waitFor(() => {
        expect(mockOnSave).toHaveBeenCalledWith([]);
      });
    });
  });

  describe("close functionality", () => {
    it("calls onClose when clicking close button", async () => {
      const user = userEvent.setup();
      renderModal();

      const closeButton = screen.getAllByRole("button", { name: /close/i })[0];
      await user.click(closeButton);

      expect(mockOnClose).toHaveBeenCalled();
    });

    it("calls onClose when clicking cancel button", async () => {
      const user = userEvent.setup();
      renderModal();

      const cancelButton = screen.getByRole("button", { name: /cancel/i });
      await user.click(cancelButton);

      expect(mockOnClose).toHaveBeenCalled();
    });

    it("does not save when closing with unsaved changes", async () => {
      const user = userEvent.setup();
      renderModal();

      const checkboxes = screen.getAllByRole("checkbox");
      await user.click(checkboxes[0]);

      const cancelButton = screen.getByRole("button", { name: /cancel/i });
      await user.click(cancelButton);

      expect(mockOnSave).not.toHaveBeenCalled();
      expect(mockOnClose).toHaveBeenCalled();
    });
  });

  describe("create new auth method link", () => {
    it("shows create new link when methods exist", () => {
      renderModal();

      expect(
        screen.getByRole("button", {
          name: /create a new authentication method/i,
        })
      ).toBeInTheDocument();
    });

    it("has button to create new auth method when methods exist", () => {
      renderModal();

      const createButton = screen.getByRole("button", {
        name: /create a new authentication method/i,
      });
      expect(createButton).toBeInTheDocument();
      expect(createButton).not.toBeDisabled();
    });

    it("shows link to project settings", () => {
      renderModal();

      const settingsLink = screen.getByRole("link", {
        name: /project settings/i,
      });
      expect(settingsLink).toHaveAttribute(
        "href",
        "/projects/project-1/settings#webhook_security"
      );
      expect(settingsLink).toHaveAttribute("target", "_blank");
      expect(settingsLink).toHaveAttribute("rel", "noopener noreferrer");
    });
  });

  describe("button state management", () => {
    it("disables buttons during save operation", async () => {
      const user = userEvent.setup();
      let resolveOnSave: () => void;
      const delayedOnSave = vi.fn(
        () =>
          new Promise<void>(resolve => {
            resolveOnSave = resolve;
          })
      );

      renderModal({ onSave: delayedOnSave });

      const checkboxes = screen.getAllByRole("checkbox");
      await user.click(checkboxes[0]);

      const saveButton = screen.getByRole("button", { name: /save/i });
      const cancelButton = screen.getByRole("button", { name: /cancel/i });

      await user.click(saveButton);

      expect(saveButton).toBeDisabled();
      expect(cancelButton).toBeDisabled();

      resolveOnSave!();
    });
  });

  describe("accessibility", () => {
    it("has proper ARIA labels", () => {
      renderModal();

      const dialog = screen.getByRole("dialog");
      expect(dialog).toBeInTheDocument();
    });

    it("supports keyboard navigation", async () => {
      const user = userEvent.setup();
      renderModal();

      const checkboxes = screen.getAllByRole("checkbox");

      // Tab through elements until we reach the first checkbox
      await user.tab(); // Close button
      await user.tab(); // First checkbox
      expect(checkboxes[0]).toHaveFocus();

      await user.keyboard(" ");
      expect(checkboxes[0]).toBeChecked();
    });

    it("has descriptive button text", () => {
      renderModal();

      expect(screen.getByText("Save")).toBeInTheDocument();
      expect(screen.getByText("Cancel")).toBeInTheDocument();
    });
  });
});
