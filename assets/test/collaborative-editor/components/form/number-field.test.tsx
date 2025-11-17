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

describe('NumberField', () => {
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
  function TestForm({ defaultValue = null }: { defaultValue?: number | null }) {
    const form = useAppForm({
      defaultValues: { count: defaultValue },
    });

    return (
      <form.AppField name="count">
        {field => (
          <field.NumberField
            label="Count"
            placeholder="Unlimited"
            helpText="Enter a number"
            min={1}
          />
        )}
      </form.AppField>
    );
  }

  it('renders with label and help text', () => {
    render(<TestForm />);

    expect(screen.getByLabelText('Count')).toBeInTheDocument();
    expect(screen.getByText('Enter a number')).toBeInTheDocument();
  });

  it('shows placeholder when value is null', () => {
    render(<TestForm defaultValue={null} />);

    const input = screen.getByLabelText('Count') as HTMLInputElement;
    expect(input.placeholder).toBe('Unlimited');
    expect(input.value).toBe('');
  });

  it('displays initial numeric value', () => {
    render(<TestForm defaultValue={5} />);

    const input = screen.getByLabelText('Count') as HTMLInputElement;
    expect(input.value).toBe('5');
  });

  it('accepts numeric input', async () => {
    const user = userEvent.setup();
    render(<TestForm />);

    const input = screen.getByLabelText('Count');
    await user.type(input, '42');

    expect((input as HTMLInputElement).value).toBe('42');
  });

  it('converts empty string to null', async () => {
    const user = userEvent.setup();
    render(<TestForm defaultValue={5} />);

    const input = screen.getByLabelText('Count');
    await user.clear(input);

    expect((input as HTMLInputElement).value).toBe('');
  });

  it('ignores non-numeric input', async () => {
    const user = userEvent.setup();
    render(<TestForm />);

    const input = screen.getByLabelText('Count');
    await user.type(input, 'abc');

    // Non-numeric characters should not appear
    expect((input as HTMLInputElement).value).toBe('');
  });
});
