import { render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { useAppForm } from '../../../../js/collaborative-editor/components/form';
import * as useWorkflowModule from '../../../../js/collaborative-editor/hooks/useWorkflow';

// Mock useWorkflowState and useWorkflowActions (required by useAppForm's
// useValidation hook, which reads from the collaborative workflow store)
vi.mock('../../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowState: vi.fn(),
  useWorkflowActions: vi.fn(() => ({
    setClientErrors: vi.fn(),
  })),
}));

describe('TextField', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
      (selector?: (state: any) => any) => {
        const state = {
          workflow: { id: 'w-1', errors: {} },
          jobs: [],
          triggers: [],
          edges: [],
        };
        return selector ? selector(state) : state;
      }
    );
  });

  function TestForm({ defaultValue = '' }: { defaultValue?: string }) {
    const form = useAppForm({
      defaultValues: { name: defaultValue },
    });

    return (
      <form.AppField name="name">
        {field => <field.TextField label="Name" placeholder="Enter a name" />}
      </form.AppField>
    );
  }

  it('renders with label, placeholder, and autoComplete="off"', () => {
    render(<TestForm />);

    const input = screen.getByLabelText('Name') as HTMLInputElement;
    expect(input).toBeInTheDocument();
    expect(input.placeholder).toBe('Enter a name');
    expect(input).toHaveAttribute('autocomplete', 'off');
  });

  it('displays initial value', () => {
    render(<TestForm defaultValue="hello" />);

    const input = screen.getByLabelText('Name') as HTMLInputElement;
    expect(input.value).toBe('hello');
  });
});
