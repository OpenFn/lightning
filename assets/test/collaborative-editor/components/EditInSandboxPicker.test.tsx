// Tests for the sandbox picker modal: create/list/join affordances, in-flight and error handling.

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { format } from 'date-fns';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { EditInSandboxPicker } from '../../../js/collaborative-editor/components/EditInSandboxPicker';
import { ChannelRequestError } from '../../../js/collaborative-editor/lib/errors';
import type { Sandbox } from '../../../js/collaborative-editor/types/workflow';

const listSandboxes = vi.fn<() => Promise<Sandbox[]>>();
const editInSandbox =
  vi.fn<
    (name?: string) => Promise<{ project_id: string; workflow_id: string }>
  >();

vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowActions: () => ({ listSandboxes, editInSandbox }),
}));

const notifyAlert = vi.fn<(opts: { title: string; description?: unknown }) => void>();
vi.mock('../../../js/collaborative-editor/lib/notifications', () => ({
  notifications: {
    alert: (opts: { title: string; description?: unknown }) => {
      notifyAlert(opts);
    },
  },
}));

// Stub the hard-navigation the picker performs on create/join.
function stubNavigation() {
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
  return {
    hrefSetter,
    restore: () => {
      Object.defineProperty(window, 'location', {
        configurable: true,
        value: originalLocation,
      });
    },
  };
}

const CREATED_A = '2025-01-15T14:30:00Z';
const CREATED_B = '2025-02-20T09:05:00Z';

// The picker formats the creation timestamp with date-fns in the runner's local
// timezone; derive the expected label the same way so the assertion is stable.
const createdLabel = (iso: string) =>
  `Created ${format(new Date(iso), 'd MMM yyyy, HH:mm')}`;

const sandboxes: Sandbox[] = [
  {
    id: 'sandbox-a',
    name: 'Alpha sandbox',
    color: null,
    inserted_at: CREATED_A,
    updated_at: new Date().toISOString(),
    creator: { id: 'u1', name: 'Ada Lovelace' },
    workflow_id: 'wf-clone-a',
  },
  {
    id: 'sandbox-b',
    name: 'Beta sandbox',
    color: '#ff0000',
    inserted_at: CREATED_B,
    updated_at: new Date().toISOString(),
    creator: { id: 'u2', email: 'grace@example.com' },
    workflow_id: 'wf-clone-b',
  },
];

describe('EditInSandboxPicker', () => {
  beforeEach(() => {
    listSandboxes.mockReset();
    editInSandbox.mockReset();
    notifyAlert.mockReset();
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

    // With nothing joinable, the whole join section stays hidden.
    await waitFor(() => {
      expect(
        screen.queryByTestId('sandbox-list-loading')
      ).not.toBeInTheDocument();
    });
    expect(screen.queryByText('Join an active sandbox')).not.toBeInTheDocument();
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

  test('shows the creator avatar, name and creation date on each row', async () => {
    listSandboxes.mockResolvedValue(sandboxes);

    render(<EditInSandboxPicker isOpen onClose={() => {}} />);

    await waitFor(() => {
      expect(screen.getByTestId('sandbox-list')).toBeInTheDocument();
    });

    // Creator name (or email) and initials avatar, not collaborator circles.
    expect(screen.getByText('Ada Lovelace')).toBeInTheDocument();
    expect(screen.getByText('AL')).toBeInTheDocument();
    expect(screen.getByText('grace@example.com')).toBeInTheDocument();

    // Each row's metadata line carries the creation date and the creator name.
    expect(screen.getByText(createdLabel(CREATED_A))).toBeInTheDocument();
    expect(screen.getByText(createdLabel(CREATED_B))).toBeInTheDocument();
    const alphaRow = screen.getByText('Alpha sandbox').closest('li');
    expect(alphaRow).toHaveTextContent(createdLabel(CREATED_A));
    expect(alphaRow).toHaveTextContent('Ada Lovelace');

    // The "edited … ago" line is gone.
    expect(screen.queryByText(/edited/i)).not.toBeInTheDocument();
  });

  test('renders the creation date but no avatar when the creator is unknown', async () => {
    listSandboxes.mockResolvedValue([
      {
        id: 'sandbox-c',
        name: 'Gamma sandbox',
        color: null,
        inserted_at: CREATED_A,
        updated_at: new Date().toISOString(),
        creator: null,
        workflow_id: 'wf-clone-c',
      },
    ]);

    render(<EditInSandboxPicker isOpen onClose={() => {}} />);

    await waitFor(() => {
      expect(screen.getByTestId('sandbox-list')).toBeInTheDocument();
    });

    expect(screen.getByText(createdLabel(CREATED_A))).toBeInTheDocument();
    // No initials avatar is rendered for a null creator.
    expect(screen.queryByText('AL')).not.toBeInTheDocument();
  });

  test('hides the join section when no listed sandbox is joinable', async () => {
    listSandboxes.mockResolvedValue([
      {
        id: 'sandbox-x',
        name: 'X sandbox',
        color: null,
        inserted_at: CREATED_A,
        updated_at: new Date().toISOString(),
        creator: { id: 'u9', name: 'Nobody Here' },
        workflow_id: null,
      },
    ]);

    render(<EditInSandboxPicker isOpen onClose={() => {}} />);

    await waitFor(() => {
      expect(listSandboxes).toHaveBeenCalledTimes(1);
    });

    await waitFor(() => {
      expect(
        screen.queryByTestId('sandbox-list-loading')
      ).not.toBeInTheDocument();
    });
    expect(screen.queryByText('Join an active sandbox')).not.toBeInTheDocument();
    expect(screen.queryByTestId('sandbox-list')).not.toBeInTheDocument();
  });

  test('lists only joinable sandboxes, each with an enabled join button', async () => {
    listSandboxes.mockResolvedValue([
      {
        id: 'joinable',
        name: 'Joinable sandbox',
        color: null,
        inserted_at: CREATED_A,
        updated_at: new Date().toISOString(),
        creator: { id: 'u1', name: 'Ada Lovelace' },
        workflow_id: 'wf-clone-a',
      },
      {
        id: 'no-clone',
        name: 'No-clone sandbox',
        color: null,
        inserted_at: CREATED_B,
        updated_at: new Date().toISOString(),
        creator: { id: 'u2', email: 'grace@example.com' },
        workflow_id: null,
      },
    ]);

    render(<EditInSandboxPicker isOpen onClose={() => {}} />);

    await waitFor(() => {
      expect(screen.getByTestId('sandbox-list')).toBeInTheDocument();
    });

    // The non-joinable sandbox (workflow_id null) is dropped entirely.
    const rows = screen.getAllByTestId('sandbox-row');
    expect(rows).toHaveLength(1);
    expect(rows[0]).toHaveTextContent('Joinable sandbox');
    expect(screen.queryByText('No-clone sandbox')).not.toBeInTheDocument();

    const joinButtons = screen.getAllByTestId('join-sandbox-button');
    expect(joinButtons).toHaveLength(1);
    expect(joinButtons[0]).toBeEnabled();
  });

  test('disables create until a non-empty name is entered', async () => {
    const user = userEvent.setup();
    listSandboxes.mockResolvedValue([]);

    render(<EditInSandboxPicker isOpen onClose={() => {}} />);

    const button = screen.getByTestId('create-sandbox-button');
    const input = screen.getByPlaceholderText('Sandbox name');

    // Blank -> disabled.
    expect(button).toBeDisabled();

    // Whitespace only -> still disabled.
    await user.type(input, '   ');
    expect(button).toBeDisabled();

    // Real characters -> enabled.
    await user.type(input, 'My SB');
    expect(button).toBeEnabled();

    // Clearing back to blank -> disabled again.
    await user.clear(input);
    expect(button).toBeDisabled();
  });

  test('creating a sandbox navigates to the new project editor', async () => {
    const user = userEvent.setup();
    listSandboxes.mockResolvedValue([]);
    editInSandbox.mockResolvedValue({
      project_id: 'new-project',
      workflow_id: 'new-workflow',
    });

    const nav = stubNavigation();

    try {
      render(<EditInSandboxPicker isOpen onClose={() => {}} />);

      await user.type(screen.getByPlaceholderText('Sandbox name'), 'My SB');
      await user.click(screen.getByTestId('create-sandbox-button'));

      await waitFor(() => {
        expect(editInSandbox).toHaveBeenCalledTimes(1);
      });
      await waitFor(() => {
        expect(nav.hrefSetter).toHaveBeenCalledWith(
          '/projects/new-project/w/new-workflow'
        );
      });
    } finally {
      nav.restore();
    }
  });

  test('surfaces a notification when the sandbox list fails to load', async () => {
    listSandboxes.mockRejectedValue(new Error('boom'));

    render(<EditInSandboxPicker isOpen onClose={() => {}} />);

    await waitFor(() => {
      expect(notifyAlert).toHaveBeenCalledWith(
        expect.objectContaining({ title: 'Could not load sandboxes' })
      );
    });
  });

  test('create failure re-enables the button and surfaces the field error', async () => {
    const user = userEvent.setup();
    listSandboxes.mockResolvedValue([]);
    // A duplicate name is keyed under `name`, not `base`; the formatter must
    // still surface it rather than falling back to the generic message.
    editInSandbox.mockRejectedValue(
      new ChannelRequestError('validation_error', {
        name: ['has already been taken'],
      })
    );

    render(<EditInSandboxPicker isOpen onClose={() => {}} />);

    await user.type(screen.getByPlaceholderText('Sandbox name'), 'My SB');
    await user.click(screen.getByTestId('create-sandbox-button'));

    await waitFor(() => {
      expect(editInSandbox).toHaveBeenCalledTimes(1);
    });

    // Button returns from the pending label to enabled.
    const button = screen.getByTestId('create-sandbox-button');
    await waitFor(() => {
      expect(button).toHaveTextContent('Create sandbox');
    });
    expect(button).toBeEnabled();

    // The field-keyed message reaches the toast via formatChannelErrorMessage.
    const lastCall = notifyAlert.mock.calls.at(-1);
    expect(lastCall?.[0].title).toBe('Could not create a sandbox');
    expect(lastCall?.[0].description).toContain('has already been taken');
  });

  test('disables the input and button while a create is in flight', async () => {
    const user = userEvent.setup();
    listSandboxes.mockResolvedValue([]);
    // Never-resolving promise keeps the create pending.
    editInSandbox.mockReturnValue(new Promise(() => {}));

    render(<EditInSandboxPicker isOpen onClose={() => {}} />);

    await user.type(screen.getByPlaceholderText('Sandbox name'), 'My SB');
    await user.click(screen.getByTestId('create-sandbox-button'));

    const button = screen.getByTestId('create-sandbox-button');
    await waitFor(() => {
      expect(button).toHaveTextContent('Creating...');
    });
    expect(button).toBeDisabled();
    expect(screen.getByPlaceholderText('Sandbox name')).toBeDisabled();
  });

  test('forwards the trimmed name to the create action', async () => {
    const user = userEvent.setup();
    listSandboxes.mockResolvedValue([]);
    editInSandbox.mockResolvedValue({
      project_id: 'p',
      workflow_id: 'w',
    });

    const nav = stubNavigation();

    try {
      render(<EditInSandboxPicker isOpen onClose={() => {}} />);

      await user.type(
        screen.getByPlaceholderText('Sandbox name'),
        '  My SB  '
      );
      await user.click(screen.getByTestId('create-sandbox-button'));
      await waitFor(() => {
        expect(editInSandbox).toHaveBeenCalledWith('My SB');
      });
    } finally {
      nav.restore();
    }
  });

  test('joining an active sandbox navigates to its editor', async () => {
    const user = userEvent.setup();
    listSandboxes.mockResolvedValue(sandboxes);

    const nav = stubNavigation();

    try {
      render(<EditInSandboxPicker isOpen onClose={() => {}} />);

      await waitFor(() => {
        expect(screen.getByTestId('sandbox-list')).toBeInTheDocument();
      });

      const joinButtons = screen.getAllByTestId('join-sandbox-button');
      await user.click(joinButtons[0]);

      expect(nav.hrefSetter).toHaveBeenCalledWith(
        '/projects/sandbox-a/w/wf-clone-a'
      );
    } finally {
      nav.restore();
    }
  });
});
