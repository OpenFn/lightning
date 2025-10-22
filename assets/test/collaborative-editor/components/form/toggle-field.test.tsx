import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { useAppForm } from "../../../../js/collaborative-editor/components/form";
import { ToggleField } from "../../../../js/collaborative-editor/components/form/toggle-field";

// Mock useWorkflowState since these tests don't need server validation
vi.mock("../../../../js/collaborative-editor/hooks/useWorkflow", () => ({
  useWorkflowState: vi.fn(() => ({})),
}));

describe("ToggleField", () => {
  function TestForm({ onSubmit }: { onSubmit: (values: any) => void }) {
    const form = useAppForm({
      defaultValues: { enabled: false },
      onSubmit: async ({ value }) => onSubmit(value),
    });

    return (
      <form.AppField name="enabled">
        {field => (
          <field.ToggleField
            label="Enable Feature"
            description="Turn this feature on or off"
          />
        )}
      </form.AppField>
    );
  }

  it("renders with label and description", () => {
    render(<TestForm onSubmit={() => {}} />);

    expect(screen.getByText("Enable Feature")).toBeInTheDocument();
    expect(screen.getByText("Turn this feature on or off")).toBeInTheDocument();
  });

  it("starts in unchecked state", () => {
    render(<TestForm onSubmit={() => {}} />);

    const checkbox = screen.getByRole("checkbox");
    expect(checkbox).not.toBeChecked();
  });

  it("toggles when clicked", async () => {
    const user = userEvent.setup();
    render(<TestForm onSubmit={() => {}} />);

    const checkbox = screen.getByRole("checkbox");
    expect(checkbox).not.toBeChecked();

    await user.click(checkbox);
    expect(checkbox).toBeChecked();

    await user.click(checkbox);
    expect(checkbox).not.toBeChecked();
  });

  it("is disabled when disabled prop is true", async () => {
    function DisabledForm() {
      const form = useAppForm({
        defaultValues: { enabled: false },
      });

      return (
        <form.AppField name="enabled">
          {field => (
            <field.ToggleField label="Enable Feature" disabled={true} />
          )}
        </form.AppField>
      );
    }

    const user = userEvent.setup();
    render(<DisabledForm />);

    const checkbox = screen.getByRole("checkbox");
    expect(checkbox).toBeDisabled();

    // Try to click - should not change state
    await user.click(checkbox);
    expect(checkbox).not.toBeChecked();
  });
});
