// Tests for the sandbox picker modal: create/list/join affordances, in-flight and error handling.

import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { format } from 'date-fns';
import type { ReactElement } from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { EditInSandboxPicker } from '../../../js/collaborative-editor/components/EditInSandboxPicker';
import { KeyboardProvider } from '../../../js/collaborative-editor/keyboard';
import { ChannelRequestError } from '../../../js/collaborative-editor/lib/errors';
import type { Sandbox } from '../../../js/collaborative-editor/types/workflow';

// The picker registers a MODAL-priority Escape handler, so it must render inside
// a KeyboardProvider (useKeyboardShortcut throws otherwise).
const renderPicker = (ui: ReactElement) =>
  render(ui, { wrapper: KeyboardProvider });

const listSandboxes = vi.fn<() => Promise<Sandbox[]>>();
const editInSandbox =
  vi.fn<
    (name?: string) => Promise<{ project_id: string; workflow_id: string }>
  >();

vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowActions: () => ({ listSandboxes, editInSandbox }),
}));

const notifyAlert =
  vi.fn<(opts: { title: string; description?: unknown }) => void>();
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

// The picker shows a relative "Created … ago" label and reveals the exact
// timestamp through the shared Tooltip on hover. Derive that exact label the
// same way the component does so the assertion is stable across timezones.
const exactTimestamp = (iso: string) =>
  format(new Date(iso), 'd MMM yyyy, HH:mm');

const sandboxes: Sandbox[] = [
  {
    id: 'sandbox-a',
    name: 'Alpha sandbox',
    color: null,
    inserted_at: CREATED_A,
    updated_at: new Date().toISOString(),
    owner: { id: 'u1', name: 'Ada Lovelace' },
    workflow_id: 'wf-clone-a',
  },
  {
    id: 'sandbox-b',
    name: 'Beta sandbox',
    color: '#ff0000',
    inserted_at: CREATED_B,
    updated_at: new Date().toISOString(),
    owner: { id: 'u2', email: 'grace@example.com' },
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

    renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);

    expect(screen.getByText('Create a new sandbox')).toBeInTheDocument();
    expect(
      screen.getByPlaceholderText('e.g. Test new changes')
    ).toBeInTheDocument();
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
    expect(
      screen.queryByText('Join an active sandbox')
    ).not.toBeInTheDocument();
  });

  test('does not fetch when closed', () => {
    renderPicker(<EditInSandboxPicker isOpen={false} onClose={() => {}} />);
    expect(listSandboxes).not.toHaveBeenCalled();
  });

  test('lists active sandboxes in returned order', async () => {
    listSandboxes.mockResolvedValue(sandboxes);

    renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);

    await waitFor(() => {
      expect(screen.getByTestId('sandbox-list')).toBeInTheDocument();
    });

    const rows = screen.getAllByTestId('sandbox-row');
    expect(rows).toHaveLength(2);
    expect(rows[0]).toHaveTextContent('Alpha sandbox');
    expect(rows[1]).toHaveTextContent('Beta sandbox');
  });

  test('shows the owner name, colour stripe and creation date on each row', async () => {
    const user = userEvent.setup();
    listSandboxes.mockResolvedValue(sandboxes);

    renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);

    await waitFor(() => {
      expect(screen.getByTestId('sandbox-list')).toBeInTheDocument();
    });

    // Creator name (or email) anchors each row's metadata line.
    expect(screen.getByText('Ada Lovelace')).toBeInTheDocument();
    expect(screen.getByText('grace@example.com')).toBeInTheDocument();

    // Alpha (no colour) leads with the fallback grey stripe; the row shows a
    // relative "Created … ago" label, then "by", then the owner name (each a
    // separate span spaced by the flex gap).
    const alphaRow = screen.getByText('Alpha sandbox').closest('li');
    expect(alphaRow).not.toBeNull();
    expect(alphaRow).toHaveTextContent(/Created .+ ago/);
    expect(within(alphaRow!).getByText('by')).toBeInTheDocument();
    expect(alphaRow).toHaveTextContent('Ada Lovelace');
    expect(alphaRow!.querySelector('span[style]')).toHaveStyle({
      backgroundColor: '#e5e7eb',
    });

    // Beta carries an explicit colour; its stripe paints that colour.
    const betaRow = screen.getByText('Beta sandbox').closest('li');
    expect(betaRow).not.toBeNull();
    expect(betaRow!.querySelector('span[style]')).toHaveStyle({
      backgroundColor: '#ff0000',
    });

    // The exact timestamp is not a native title anymore; it lives in the shared
    // Tooltip, revealed by hovering the relative-time trigger.
    await user.hover(alphaRow!.querySelector('[data-state]') as Element);
    expect(
      (await screen.findAllByText(exactTimestamp(CREATED_A))).length
    ).toBeGreaterThan(0);

    // The "edited … ago" line is gone.
    expect(screen.queryByText(/edited/i)).not.toBeInTheDocument();
  });

  test('renders the colour stripe and creation date when the owner is unknown', async () => {
    const user = userEvent.setup();
    listSandboxes.mockResolvedValue([
      {
        id: 'sandbox-c',
        name: 'Gamma sandbox',
        color: null,
        inserted_at: CREATED_A,
        updated_at: new Date().toISOString(),
        owner: null,
        workflow_id: 'wf-clone-c',
      },
    ]);

    renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);

    await waitFor(() => {
      expect(screen.getByTestId('sandbox-list')).toBeInTheDocument();
    });

    const row = screen.getByText('Gamma sandbox').closest('li');
    expect(row).not.toBeNull();
    // Relative created label; the colour stripe still renders (fallback grey)
    // even without an owner.
    expect(row).toHaveTextContent(/Created .+ ago/);
    expect(row!.querySelector('span[style]')).toHaveStyle({
      backgroundColor: '#e5e7eb',
    });

    // Exact timestamp is available on hover via the shared Tooltip.
    await user.hover(row!.querySelector('[data-state]') as Element);
    expect(
      (await screen.findAllByText(exactTimestamp(CREATED_A))).length
    ).toBeGreaterThan(0);
  });

  test('hides the join section when the server returns no sandboxes', async () => {
    // The server only ever returns joinable sandboxes, so an empty list means
    // there is nothing to join and the whole section stays hidden.
    listSandboxes.mockResolvedValue([]);

    renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);

    await waitFor(() => {
      expect(listSandboxes).toHaveBeenCalledTimes(1);
    });

    await waitFor(() => {
      expect(
        screen.queryByTestId('sandbox-list-loading')
      ).not.toBeInTheDocument();
    });
    expect(
      screen.queryByText('Join an active sandbox')
    ).not.toBeInTheDocument();
    expect(screen.queryByTestId('sandbox-list')).not.toBeInTheDocument();
  });

  test('renders the server-returned sandboxes, each with an enabled join button', async () => {
    // The server already filters to joinable sandboxes (each holds a clone), so
    // the client renders exactly what it receives.
    listSandboxes.mockResolvedValue([
      {
        id: 'joinable',
        name: 'Joinable sandbox',
        color: null,
        inserted_at: CREATED_A,
        updated_at: new Date().toISOString(),
        owner: { id: 'u1', name: 'Ada Lovelace' },
        workflow_id: 'wf-clone-a',
      },
    ]);

    renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);

    await waitFor(() => {
      expect(screen.getByTestId('sandbox-list')).toBeInTheDocument();
    });

    const rows = screen.getAllByTestId('sandbox-row');
    expect(rows).toHaveLength(1);
    expect(rows[0]).toHaveTextContent('Joinable sandbox');

    const joinButtons = screen.getAllByTestId('join-sandbox-button');
    expect(joinButtons).toHaveLength(1);
    expect(joinButtons[0]).toBeEnabled();
  });

  test('disables create until a non-empty name is entered', async () => {
    const user = userEvent.setup();
    listSandboxes.mockResolvedValue([]);

    renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);

    const button = screen.getByTestId('create-sandbox-button');
    const input = screen.getByPlaceholderText('e.g. Test new changes');

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
      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);

      await user.type(
        screen.getByPlaceholderText('e.g. Test new changes'),
        'My SB'
      );
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

    renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);

    await waitFor(() => {
      expect(notifyAlert).toHaveBeenCalledWith(
        expect.objectContaining({ title: 'Could not load sandboxes' })
      );
    });
  });

  test('renders a duplicate-name error inline under the input, not as a toast', async () => {
    const user = userEvent.setup();
    listSandboxes.mockResolvedValue([]);
    // A duplicate name comes back as a validation_error keyed under `name`;
    // this belongs inline under the input, never as a toast.
    editInSandbox.mockRejectedValue(
      new ChannelRequestError('validation_error', {
        name: ['has already been taken'],
      })
    );

    renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);

    const input = screen.getByPlaceholderText('e.g. Test new changes');
    await user.type(input, 'My SB');
    await user.click(screen.getByTestId('create-sandbox-button'));

    await waitFor(() => {
      expect(editInSandbox).toHaveBeenCalledTimes(1);
    });

    // The duplicate-name case renders a friendly, product-specific message
    // inline beneath the input rather than the raw server string.
    const fieldError = await screen.findByTestId('sandbox-name-error');
    expect(fieldError).toHaveTextContent(
      'A sandbox with this name exists already'
    );
    expect(fieldError).not.toHaveTextContent('has already been taken');

    // The input is put into an error state and points at the error text.
    expect(input).toHaveAttribute('aria-invalid', 'true');
    expect(input).toHaveClass('ring-red-300');

    // A duplicate name never toasts.
    expect(notifyAlert).not.toHaveBeenCalled();

    // Button returns from the pending label to enabled.
    const button = screen.getByTestId('create-sandbox-button');
    await waitFor(() => {
      expect(button).toHaveTextContent('Create sandbox');
    });
    expect(button).toBeEnabled();

    // Editing the name clears the inline error and the error styling.
    await user.type(input, '2');
    expect(screen.queryByTestId('sandbox-name-error')).not.toBeInTheDocument();
    expect(input).not.toHaveAttribute('aria-invalid');
    expect(input).not.toHaveClass('ring-red-300');
  });

  test('routes an unexpected create error to a toast, not the inline field', async () => {
    const user = userEvent.setup();
    listSandboxes.mockResolvedValue([]);
    // A non-validation (system) error is not a name problem; it must surface as
    // a toast and leave the input in its normal state.
    editInSandbox.mockRejectedValue(
      new ChannelRequestError('internal_error', {
        base: ['something went wrong'],
      })
    );

    renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);

    const input = screen.getByPlaceholderText('e.g. Test new changes');
    await user.type(input, 'My SB');
    await user.click(screen.getByTestId('create-sandbox-button'));

    await waitFor(() => {
      expect(notifyAlert).toHaveBeenCalledWith(
        expect.objectContaining({ title: 'Could not create a sandbox' })
      );
    });

    expect(screen.queryByTestId('sandbox-name-error')).not.toBeInTheDocument();
    expect(input).not.toHaveAttribute('aria-invalid');
  });

  test('pressing Enter in the name input submits the create action', async () => {
    const user = userEvent.setup();
    listSandboxes.mockResolvedValue([]);
    editInSandbox.mockResolvedValue({
      project_id: 'new-project',
      workflow_id: 'new-workflow',
    });

    const nav = stubNavigation();

    try {
      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);

      // Focus the input and press Enter; no click on "Create sandbox".
      await user.type(
        screen.getByPlaceholderText('e.g. Test new changes'),
        'My SB{Enter}'
      );

      await waitFor(() => {
        expect(editInSandbox).toHaveBeenCalledWith('My SB');
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

  test('pressing Enter with an empty name does not submit', async () => {
    const user = userEvent.setup();
    listSandboxes.mockResolvedValue([]);

    renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);

    const input = screen.getByPlaceholderText('e.g. Test new changes');
    input.focus();
    await user.keyboard('{Enter}');

    expect(editInSandbox).not.toHaveBeenCalled();
  });

  test('disables the input and button while a create is in flight', async () => {
    const user = userEvent.setup();
    listSandboxes.mockResolvedValue([]);
    // Never-resolving promise keeps the create pending.
    editInSandbox.mockReturnValue(new Promise(() => {}));

    renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);

    await user.type(
      screen.getByPlaceholderText('e.g. Test new changes'),
      'My SB'
    );
    await user.click(screen.getByTestId('create-sandbox-button'));

    const button = screen.getByTestId('create-sandbox-button');
    await waitFor(() => {
      expect(button).toHaveTextContent('Creating...');
    });
    expect(button).toBeDisabled();
    expect(screen.getByPlaceholderText('e.g. Test new changes')).toBeDisabled();
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
      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);

      await user.type(
        screen.getByPlaceholderText('e.g. Test new changes'),
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
      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);

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

  test('pressing Escape closes the picker', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    listSandboxes.mockResolvedValue([]);

    renderPicker(<EditInSandboxPicker isOpen onClose={onClose} />);

    // The MODAL-priority handler runs ahead of the IDE/inspector handlers, so
    // Escape reaches the picker even though it lives inside the editor. In
    // isolation Headless UI's own default also fires (no IDE handler suppresses
    // it here), so we assert the picker closed rather than a precise call count.
    await user.keyboard('{Escape}');

    expect(onClose).toHaveBeenCalled();
  });
});
