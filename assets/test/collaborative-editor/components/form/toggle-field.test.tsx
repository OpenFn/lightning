import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { useAppForm } from '../../../../js/collaborative-editor/components/form';
import * as useWorkflowModule from '../../../../js/collaborative-editor/hooks/useWorkflow';

// Mock useWorkflowState and useWorkflowActions
vi.mock('../../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowState: vi.fn(),
  useWorkflowActions: vi.fn(() => ({
    setClientErrors: vi.fn(),
  })),
}));

describe('ToggleField', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Mock useWorkflowState to return workflow with empty errors
    const mockFn = vi.fn(selector => {
      const state = {
        workflow: { id: 'w-1', errors: {} },
        jobs: [],
        triggers: [],
        edges: [],
      };
      return selector ? selector(state) : state;
    });
    vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
      mockFn as any
    );
  });
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

  it('renders with label and description', () => {
    render(<TestForm onSubmit={() => {}} />);

    expect(screen.getByText('Enable Feature')).toBeInTheDocument();
    expect(screen.getByText('Turn this feature on or off')).toBeInTheDocument();
  });

  it('starts in unchecked state', () => {
    render(<TestForm onSubmit={() => {}} />);

    const checkbox = screen.getByRole('checkbox');
    expect(checkbox).not.toBeChecked();
  });

  it('toggles when clicked', async () => {
    const user = userEvent.setup();
    render(<TestForm onSubmit={() => {}} />);

    const checkbox = screen.getByRole('checkbox');
    expect(checkbox).not.toBeChecked();

    await user.click(checkbox);
    expect(checkbox).toBeChecked();

    await user.click(checkbox);
    expect(checkbox).not.toBeChecked();
  });

  it('is disabled when disabled prop is true', async () => {
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

    const checkbox = screen.getByRole('checkbox');
    expect(checkbox).toBeDisabled();

    // Try to click - should not change state
    await user.click(checkbox);
    expect(checkbox).not.toBeChecked();
  });
});
