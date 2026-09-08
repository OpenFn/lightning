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
const editInSandbox = vi.fn<
  (
    name?: string,
    start?: unknown
  ) => Promise<{
    project_id: string;
    workflow_id: string;
    dataclip_id: string | null;
  }>
>();

let jobs: { id: string }[] = [];

vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowActions: () => ({ listSandboxes, editInSandbox }),
  useWorkflowState: (selector: (state: unknown) => unknown) =>
    selector({ jobs }),
}));

let activeRun: {
  id: string;
  steps: { input_dataclip_id: string | null; job_id: string | null }[];
} | null = null;

let runHistory: {
  id: string;
  runs: { id: string; version_number: number | null }[];
}[] = [];

vi.mock('../../../js/collaborative-editor/hooks/useHistory', () => ({
  useActiveRun: () => activeRun,
  useHistory: () => runHistory,
}));

let versions: {
  version_number: number;
  lock_version: number;
  is_latest: boolean;
}[] = [];
const requestVersionsMock = vi.fn();

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useProject: () => ({ id: 'project-1' }),
  useVersions: () => versions,
  useRequestVersions: () => requestVersionsMock,
}));

const searchDataclipsMock = vi.fn();
const getDataclipBodyMock = vi.fn();
const getRunDataclipMock = vi.fn();

vi.mock('../../../js/collaborative-editor/api/dataclips', () => ({
  searchDataclips: (...args: unknown[]) => searchDataclipsMock(...args),
  getDataclipBody: (...args: unknown[]) => getDataclipBodyMock(...args),
  getRunDataclip: (...args: unknown[]) => getRunDataclipMock(...args),
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
    searchDataclipsMock.mockReset();
    getDataclipBodyMock.mockReset();
    getRunDataclipMock.mockReset();
    getRunDataclipMock.mockResolvedValue({
      dataclip: { id: 'dc-1', wiped_at: null },
    });
    runHistory = [];
    listSandboxes.mockResolvedValue([]);
    searchDataclipsMock.mockResolvedValue({ data: [] });
    getDataclipBodyMock.mockResolvedValue('{}');
    activeRun = null;
    jobs = [{ id: 'job-1' }];
    versions = [];
    requestVersionsMock.mockReset();
    requestVersionsMock.mockResolvedValue(undefined);
  });

  describe('choosing what to start with', () => {
    const typeName = async (user: ReturnType<typeof userEvent.setup>) => {
      await user.type(
        screen.getByPlaceholderText('e.g. Test new changes'),
        'My SB'
      );
    };

    test("offers this run's input only while a run is open", async () => {
      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);

      expect(screen.queryByLabelText(/this run's input/i)).toBeNull();
    });

    test("does not offer the run's input when its step has no job", async () => {
      activeRun = {
        id: 'abcdef123456',
        steps: [{ input_dataclip_id: 'dc-1', job_id: null }],
      };

      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);

      // Offering it could only create an empty sandbox while reporting success.
      expect(screen.queryByLabelText(/this run's input/i)).toBeNull();
    });

    test("carries the reviewed body through when the run's input is chosen", async () => {
      const user = userEvent.setup();
      activeRun = {
        id: 'abcdef123456',
        steps: [{ input_dataclip_id: 'dc-1', job_id: 'job-1' }],
      };
      getDataclipBodyMock.mockResolvedValue('{"email":"real@example.com"}');
      editInSandbox.mockResolvedValue({
        project_id: 'p2',
        workflow_id: 'w2',
        dataclip_id: 'dc-new',
      });

      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);
      await typeName(user);

      await user.click(screen.getByLabelText(/this run's input/i));
      await user.click(screen.getByTestId('create-sandbox-button'));

      // The body is shown before it travels, and can be edited.
      const body = await screen.findByTestId('review-body');
      expect(body).toHaveValue('{"email":"real@example.com"}');

      await user.clear(body);
      await user.type(body, '{{"email":"redacted"}');
      await user.click(screen.getByTestId('create-from-review-button'));

      await waitFor(() => {
        expect(editInSandbox).toHaveBeenCalledWith('My SB', {
          body: '{"email":"redacted"}',
          bodyName: 'Input from run abcdef',
        });
      });
    });

    test('keeps a redaction across Back and Continue', async () => {
      const user = userEvent.setup();
      activeRun = {
        id: 'abcdef123456',
        steps: [{ input_dataclip_id: 'dc-1', job_id: 'job-1' }],
      };
      getDataclipBodyMock.mockResolvedValue('{"email":"real@example.com"}');

      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);
      await user.type(
        screen.getByPlaceholderText('e.g. Test new changes'),
        'My SB'
      );

      await user.click(screen.getByLabelText(/this run's input/i));
      await user.click(screen.getByTestId('create-sandbox-button'));

      const body = await screen.findByTestId('review-body');
      await user.clear(body);
      await user.type(body, '{{"email":"redacted"}');

      await user.click(screen.getByRole('button', { name: 'Back' }));
      await user.click(screen.getByTestId('create-sandbox-button'));

      // Refetching here would put the production email back in front of them,
      // which is the one thing this screen exists to prevent.
      expect(await screen.findByTestId('review-body')).toHaveValue(
        '{"email":"redacted"}'
      );
    });

    test('stays usable after Back and Continue', async () => {
      const user = userEvent.setup();
      activeRun = {
        id: 'abcdef123456',
        steps: [{ input_dataclip_id: 'dc-1', job_id: 'job-1' }],
      };
      getDataclipBodyMock.mockResolvedValue('{"a":1}');

      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);
      await user.type(
        screen.getByPlaceholderText('e.g. Test new changes'),
        'My SB'
      );

      await user.click(screen.getByLabelText(/this run's input/i));
      await user.click(screen.getByTestId('create-sandbox-button'));
      await screen.findByTestId('review-body');

      await user.click(screen.getByRole('button', { name: 'Back' }));
      await user.click(screen.getByTestId('create-sandbox-button'));
      await screen.findByTestId('review-body');
      await user.click(screen.getByRole('button', { name: 'Back' }));

      // Back is what a rejected name tells the person to do, so the button has
      // to survive the round trip rather than stick on "Loading...".
      const submit = screen.getByTestId('create-sandbox-button');
      expect(submit).toBeEnabled();
      expect(submit).not.toHaveTextContent('Loading');
    });

    test('keeps an emptied body across Back and Continue', async () => {
      const user = userEvent.setup();
      activeRun = {
        id: 'abcdef123456',
        steps: [{ input_dataclip_id: 'dc-1', job_id: 'job-1' }],
      };
      getDataclipBodyMock.mockResolvedValue('{"email":"real@example.com"}');

      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);
      await user.type(
        screen.getByPlaceholderText('e.g. Test new changes'),
        'My SB'
      );

      await user.click(screen.getByLabelText(/this run's input/i));
      await user.click(screen.getByTestId('create-sandbox-button'));

      // Clearing it is a redaction. Treating an empty box as "not loaded yet"
      // hands the production body straight back.
      await user.clear(await screen.findByTestId('review-body'));
      await user.click(screen.getByRole('button', { name: 'Back' }));
      await user.click(screen.getByTestId('create-sandbox-button'));

      expect(await screen.findByTestId('review-body')).toHaveValue('');
    });

    test('loads the body again after the dialog is closed and reopened', async () => {
      const user = userEvent.setup();
      activeRun = {
        id: 'abcdef123456',
        steps: [{ input_dataclip_id: 'dc-1', job_id: 'job-1' }],
      };
      getDataclipBodyMock.mockResolvedValue('{"a":1}');

      const { rerender } = renderPicker(
        <EditInSandboxPicker isOpen onClose={() => {}} />
      );
      await user.type(
        screen.getByPlaceholderText('e.g. Test new changes'),
        'My SB'
      );

      await user.click(screen.getByLabelText(/this run's input/i));
      await user.click(screen.getByTestId('create-sandbox-button'));
      expect(await screen.findByTestId('review-body')).toHaveValue('{"a":1}');

      rerender(<EditInSandboxPicker isOpen={false} onClose={() => {}} />);
      rerender(<EditInSandboxPicker isOpen onClose={() => {}} />);

      await user.type(
        screen.getByPlaceholderText('e.g. Test new changes'),
        'My SB'
      );
      await user.click(screen.getByLabelText(/this run's input/i));
      await user.click(screen.getByTestId('create-sandbox-button'));

      // A flag left set across a reopen skips the fetch and shows an empty
      // review step that can never recover.
      expect(await screen.findByTestId('review-body')).toHaveValue('{"a":1}');
    });

    test('does not strand the button when the dialog closes mid-fetch', async () => {
      const user = userEvent.setup();
      activeRun = {
        id: 'abcdef123456',
        steps: [{ input_dataclip_id: 'dc-1', job_id: 'job-1' }],
      };

      let release: (v: {
        dataclip: { id: string; wiped_at: null };
      }) => void = () => {};
      getRunDataclipMock.mockReturnValue(
        new Promise(resolve => {
          release = resolve;
        })
      );

      const { rerender } = renderPicker(
        <EditInSandboxPicker isOpen onClose={() => {}} />
      );
      await user.type(
        screen.getByPlaceholderText('e.g. Test new changes'),
        'My SB'
      );
      await user.click(screen.getByLabelText(/this run's input/i));
      await user.click(screen.getByTestId('create-sandbox-button'));

      rerender(<EditInSandboxPicker isOpen={false} onClose={() => {}} />);
      rerender(<EditInSandboxPicker isOpen onClose={() => {}} />);

      release({ dataclip: { id: 'dc-1', wiped_at: null } });

      await user.type(
        screen.getByPlaceholderText('e.g. Test new changes'),
        'My SB'
      );

      // A reply that lost its race must not leave the button latched on
      // "Loading..." for the rest of the page's life.
      await waitFor(() => {
        expect(screen.getByTestId('create-sandbox-button')).toBeEnabled();
      });
      expect(screen.getByTestId('create-sandbox-button')).not.toHaveTextContent(
        'Loading'
      );
    });

    test("never shows one run's body for another run", async () => {
      const user = userEvent.setup();
      activeRun = {
        id: 'aaaaaa000000',
        steps: [{ input_dataclip_id: 'dc-a', job_id: 'job-1' }],
      };
      getDataclipBodyMock.mockResolvedValue('{"from":"run-a"}');

      const { rerender } = renderPicker(
        <EditInSandboxPicker isOpen onClose={() => {}} />
      );
      await user.type(
        screen.getByPlaceholderText('e.g. Test new changes'),
        'My SB'
      );
      await user.click(screen.getByLabelText(/this run's input/i));
      await user.click(screen.getByTestId('create-sandbox-button'));
      expect(await screen.findByTestId('review-body')).toHaveValue(
        '{"from":"run-a"}'
      );

      // The run changes under the open dialog, which Back/Forward does.
      await user.click(screen.getByRole('button', { name: 'Back' }));
      activeRun = {
        id: 'bbbbbb000000',
        steps: [{ input_dataclip_id: 'dc-b', job_id: 'job-1' }],
      };
      getDataclipBodyMock.mockResolvedValue('{"from":"run-b"}');
      rerender(<EditInSandboxPicker isOpen onClose={() => {}} />);

      await user.click(screen.getByTestId('create-sandbox-button'));

      // Run A's body belongs to run A. Showing it here would ship it as B's.
      expect(await screen.findByTestId('review-body')).toHaveValue(
        '{"from":"run-b"}'
      );
    });

    test('says nothing was kept when the run has no input to copy', async () => {
      const user = userEvent.setup();
      activeRun = {
        id: 'abcdef123456',
        steps: [{ input_dataclip_id: 'dc-1', job_id: 'job-1' }],
      };
      // A wiped http_request still serves a JSON object, so the guard has to
      // read wiped_at rather than judge the body.
      getRunDataclipMock.mockResolvedValue({
        dataclip: {
          id: 'dc-1',
          wiped_at: '2026-09-01T00:00:00Z',
        },
      });
      getDataclipBodyMock.mockResolvedValue('{"data": null, "request": null}');

      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);
      await user.type(
        screen.getByPlaceholderText('e.g. Test new changes'),
        'My SB'
      );

      await user.click(screen.getByLabelText(/this run's input/i));
      await user.click(screen.getByTestId('create-sandbox-button'));

      expect(
        await screen.findByTestId('run-input-missing')
      ).toBeInTheDocument();
      expect(screen.queryByTestId('review-body')).toBeNull();
      expect(screen.getByTestId('create-sandbox-button')).toBeDisabled();
      expect(editInSandbox).not.toHaveBeenCalled();
    });

    test('refuses to create when the person edits the body into something invalid', async () => {
      const user = userEvent.setup();
      activeRun = {
        id: 'abcdef123456',
        steps: [{ input_dataclip_id: 'dc-1', job_id: 'job-1' }],
      };
      getDataclipBodyMock.mockResolvedValue('{"a":1}');

      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);
      await user.type(
        screen.getByPlaceholderText('e.g. Test new changes'),
        'My SB'
      );

      await user.click(screen.getByLabelText(/this run's input/i));
      await user.click(screen.getByTestId('create-sandbox-button'));

      const body = await screen.findByTestId('review-body');
      await user.clear(body);
      await user.type(body, '[[1,2,3]');
      await user.click(screen.getByTestId('create-from-review-button'));

      expect(screen.getByTestId('review-body-error')).toHaveTextContent(
        'This needs to be a JSON object.'
      );
      expect(editInSandbox).not.toHaveBeenCalled();
    });

    test('says which version the sandbox will fork when the run used an older one', async () => {
      const user = userEvent.setup();
      activeRun = {
        id: 'abcdef123456',
        steps: [{ input_dataclip_id: 'dc-1', job_id: 'job-1' }],
      };
      // The run's version comes from the history summaries, not from whatever
      // the editor happens to have open.
      runHistory = [
        { id: 'wo-1', runs: [{ id: 'abcdef123456', version_number: 3 }] },
      ];
      // Deliberately not newest-first, so the note has to read is_latest rather
      // than trust the order.
      versions = [
        { version_number: 3, lock_version: 4, is_latest: false },
        { version_number: 7, lock_version: 9, is_latest: true },
      ];

      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);
      await user.click(screen.getByLabelText(/this run's input/i));

      const note = screen.getByTestId('version-note');
      expect(note).toHaveTextContent(/This run used v3\./);
      expect(note).toHaveTextContent(/v7/);
    });

    test('stays quiet when the run already used the version live now', async () => {
      const user = userEvent.setup();
      activeRun = {
        id: 'abcdef123456',
        steps: [{ input_dataclip_id: 'dc-1', job_id: 'job-1' }],
      };
      runHistory = [
        { id: 'wo-1', runs: [{ id: 'abcdef123456', version_number: 7 }] },
      ];
      versions = [{ version_number: 7, lock_version: 9, is_latest: true }];

      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);
      await user.click(screen.getByLabelText(/this run's input/i));

      expect(screen.queryByTestId('version-note')).toBeNull();
    });

    test('does not mention the run when starting from something else', async () => {
      const user = userEvent.setup();
      // A run is open and it did use an older version, but the sandbox is being
      // started from a saved input, so the run has nothing to do with it.
      activeRun = {
        id: 'abcdef123456',
        steps: [{ input_dataclip_id: 'dc-1', job_id: 'job-1' }],
      };
      runHistory = [
        { id: 'wo-1', runs: [{ id: 'abcdef123456', version_number: 3 }] },
      ];
      versions = [
        { version_number: 3, lock_version: 4, is_latest: false },
        { version_number: 7, lock_version: 9, is_latest: true },
      ];

      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);
      await user.click(screen.getByLabelText(/a saved input/i));

      expect(screen.queryByTestId('version-note')).toBeNull();
    });

    test('asks for named inputs only, scoped to the project', async () => {
      const user = userEvent.setup();

      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);
      await user.click(screen.getByLabelText(/a saved input/i));

      await waitFor(() => {
        expect(searchDataclipsMock).toHaveBeenCalledWith(
          'project-1',
          'job-1',
          '',
          { named_only: true, limit: 100 }
        );
      });
    });

    test('does not offer a named dataclip a sandbox cannot copy', async () => {
      const user = userEvent.setup();
      searchDataclipsMock.mockResolvedValue({
        data: [
          { id: 'dc-step', name: 'from a step', type: 'step_result' },
          { id: 'dc-ok', name: 'known good', type: 'saved_input' },
        ],
      });

      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);
      await user.click(screen.getByLabelText(/a saved input/i));

      const saved = await screen.findByTestId('saved-inputs');

      // A step result carries whatever the previous step emitted, which is the
      // data we are trying not to move, so create would refuse it anyway.
      expect(within(saved).getByText('known good')).toBeInTheDocument();
      expect(within(saved).queryByText('from a step')).toBeNull();
    });

    test('distinguishes nothing named from nothing copyable', async () => {
      const user = userEvent.setup();
      searchDataclipsMock.mockResolvedValue({
        data: [{ id: 'dc-step', name: 'from a step', type: 'step_result' }],
      });

      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);
      await user.click(screen.getByLabelText(/a saved input/i));

      expect(await screen.findByTestId('saved-inputs-empty')).toHaveTextContent(
        /can be copied into a sandbox/i
      );
    });

    test('says a step is needed before a saved input can be picked', async () => {
      const user = userEvent.setup();
      jobs = [];

      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);
      await user.click(screen.getByLabelText(/a saved input/i));

      expect(
        screen.getByTestId('saved-inputs-unavailable')
      ).toBeInTheDocument();
    });

    test('sends the chosen saved input by id', async () => {
      const user = userEvent.setup();
      searchDataclipsMock.mockResolvedValue({
        data: [{ id: 'dc-saved', name: 'known good', type: 'saved_input' }],
      });
      editInSandbox.mockResolvedValue({
        project_id: 'p2',
        workflow_id: 'w2',
        dataclip_id: 'dc-copy',
      });

      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);
      await user.type(
        screen.getByPlaceholderText('e.g. Test new changes'),
        'My SB'
      );

      await user.click(screen.getByLabelText(/a saved input/i));
      const saved = await screen.findByTestId('saved-inputs');
      await user.click(within(saved).getByRole('radio'));
      await user.click(screen.getByTestId('create-sandbox-button'));

      await waitFor(() => {
        expect(editInSandbox).toHaveBeenCalledWith('My SB', {
          dataclipId: 'dc-saved',
        });
      });
    });

    test('lands on the run panel so the carried input is visible', async () => {
      const user = userEvent.setup();
      activeRun = {
        id: 'abcdef123456',
        steps: [{ input_dataclip_id: 'dc-1', job_id: 'job-1' }],
      };
      getDataclipBodyMock.mockResolvedValue('{"a":1}');
      editInSandbox.mockResolvedValue({
        project_id: 'p2',
        workflow_id: 'w2',
        dataclip_id: 'dc-new',
      });
      const nav = stubNavigation();

      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);
      await user.type(
        screen.getByPlaceholderText('e.g. Test new changes'),
        'My SB'
      );

      await user.click(screen.getByLabelText(/this run's input/i));
      await user.click(screen.getByTestId('create-sandbox-button'));
      await screen.findByTestId('review-body');
      await user.click(screen.getByTestId('create-from-review-button'));

      // Without panel=run the sandbox opens on a bare canvas and the input we
      // carried is selected where nobody can see it.
      await waitFor(() => {
        expect(nav.hrefSetter).toHaveBeenCalledWith(
          '/projects/p2/w/w2?panel=run&dataclip=dc-new'
        );
      });
    });

    test('will not create until a saved input is picked', async () => {
      const user = userEvent.setup();
      searchDataclipsMock.mockResolvedValue({
        data: [{ id: 'dc-saved', name: 'known good', type: 'saved_input' }],
      });

      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);
      await typeName(user);

      await user.click(screen.getByLabelText(/a saved input/i));
      await screen.findByTestId('saved-inputs');

      expect(screen.getByTestId('create-sandbox-button')).toBeDisabled();
    });

    test('says so when the project has no named inputs', async () => {
      const user = userEvent.setup();
      searchDataclipsMock.mockResolvedValue({ data: [] });

      renderPicker(<EditInSandboxPicker isOpen onClose={() => {}} />);
      await user.click(screen.getByLabelText(/a saved input/i));

      expect(
        await screen.findByTestId('saved-inputs-empty')
      ).toBeInTheDocument();
    });
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
      dataclip_id: null,
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
      dataclip_id: null,
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
        expect(editInSandbox).toHaveBeenCalledWith('My SB', {});
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
      dataclip_id: null,
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
        expect(editInSandbox).toHaveBeenCalledWith('My SB', {});
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
