/**
 * EditInSandboxPicker Component Tests
 *
 * Focused tests for the sandbox picker modal:
 * - Renders the "create new sandbox" option.
 * - Lists active sandboxes returned by the server (in order).
 * - Disables the join action when a sandbox lacks this workflow's clone.
 * - Creating a sandbox navigates to the new project's editor.
 *
 * The picker's only collaboration dependency is useWorkflowActions, which we
 * mock so we can drive listSandboxes/editInSandbox deterministically.
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { EditInSandboxPicker } from '../../../js/collaborative-editor/components/EditInSandboxPicker';
import type { Sandbox } from '../../../js/collaborative-editor/types/workflow';

const listSandboxes = vi.fn<() => Promise<Sandbox[]>>();
const editInSandbox =
  vi.fn<
    (name?: string) => Promise<{ project_id: string; workflow_id: string }>
  >();

vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowActions: () => ({ listSandboxes, editInSandbox }),
}));

const sandboxes: Sandbox[] = [
  {
    id: 'sandbox-a',
    name: 'Alpha sandbox',
    color: null,
    updated_at: new Date().toISOString(),
    collaborators: [
      { id: 'u1', name: 'Ada Lovelace' },
      { id: 'u2', email: 'grace@example.com' },
    ],
    workflow_id: 'wf-clone-a',
  },
  {
    id: 'sandbox-b',
    name: 'Beta sandbox',
    color: '#ff0000',
    updated_at: new Date().toISOString(),
    collaborators: [],
    workflow_id: null,
  },
];

describe('EditInSandboxPicker', () => {
  beforeEach(() => {
    listSandboxes.mockReset();
    editInSandbox.mockReset();
    listSandboxes.mockResolvedValue([]);
  });

  test('renders the create option and fetches sandboxes on open', async () => {
    listSandboxes.mockResolvedValue([]);

    render(<EditInSandboxPicker isOpen onClose={() => {}} />);

    expect(screen.getByText('Create a new sandbox')).toBeInTheDocument();
    expect(screen.getByTestId('create-sandbox-button')).toBeInTheDocument();

    await waitFor(() => {
      expect(listSandboxes).toHaveBeenCalledTimes(1);
    });

    // Empty state when no sandboxes exist
    await waitFor(() => {
      expect(screen.getByTestId('sandbox-list-empty')).toBeInTheDocument();
    });
  });

  test('does not fetch when closed', () => {
    render(<EditInSandboxPicker isOpen={false} onClose={() => {}} />);
    expect(listSandboxes).not.toHaveBeenCalled();
  });

  test('lists active sandboxes in returned order', async () => {
    listSandboxes.mockResolvedValue(sandboxes);

    render(<EditInSandboxPicker isOpen onClose={() => {}} />);

    await waitFor(() => {
      expect(screen.getByTestId('sandbox-list')).toBeInTheDocument();
    });

    const rows = screen.getAllByTestId('sandbox-row');
    expect(rows).toHaveLength(2);
    expect(rows[0]).toHaveTextContent('Alpha sandbox');
    expect(rows[1]).toHaveTextContent('Beta sandbox');
  });

  test('disables join when the workflow is not in that sandbox', async () => {
    listSandboxes.mockResolvedValue(sandboxes);

    render(<EditInSandboxPicker isOpen onClose={() => {}} />);

    await waitFor(() => {
      expect(screen.getByTestId('sandbox-list')).toBeInTheDocument();
    });

    const joinButtons = screen.getAllByTestId('join-sandbox-button');
    // First sandbox has a workflow clone -> enabled
    expect(joinButtons[0]).toBeEnabled();
    // Second sandbox has workflow_id null -> disabled with explanation
    expect(joinButtons[1]).toBeDisabled();
    expect(joinButtons[1]).toHaveAttribute(
      'title',
      "This workflow isn't in that sandbox"
    );
  });

  test('creating a sandbox navigates to the new project editor', async () => {
    const user = userEvent.setup();
    listSandboxes.mockResolvedValue([]);
    editInSandbox.mockResolvedValue({
      project_id: 'new-project',
      workflow_id: 'new-workflow',
    });

    const originalLocation = window.location;
    const hrefSetter = vi.fn();
    Object.defineProperty(window, 'location', {
      configurable: true,
      value: {
        ...originalLocation,
        set href(value: string) {
          hrefSetter(value);
        },
      },
    });

    try {
      render(<EditInSandboxPicker isOpen onClose={() => {}} />);

      await user.click(screen.getByTestId('create-sandbox-button'));

      await waitFor(() => {
        expect(editInSandbox).toHaveBeenCalledTimes(1);
      });
      await waitFor(() => {
        expect(hrefSetter).toHaveBeenCalledWith(
          '/projects/new-project/w/new-workflow'
        );
      });
    } finally {
      Object.defineProperty(window, 'location', {
        configurable: true,
        value: originalLocation,
      });
    }
  });
});
