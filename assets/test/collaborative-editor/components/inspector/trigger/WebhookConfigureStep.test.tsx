/**
 * WebhookConfigureStep Component Tests
 *
 * Covers logic NOT already exercised by TriggerEditWizard.test.tsx:
 *   1. Accordion state — Authentication and Response Options toggle open/closed;
 *      `initialExpand` opens the relevant section on mount.
 *   2. DOM event relay — `close_webhook_auth_modal` on #collaborative-editor-react
 *      pushes `close_webhook_auth_modal_complete` to the server.
 *   3. Response Options inputs — only rendered for `webhook_reply === 'after_completion'`;
 *      editing calls `mergeDraft` with parsed integers (empty → null).
 *   4. Async-mode warning — shows when after_completion + response config exists.
 *   5. Auth-method permission gating: the WebhookAuthMethodSelect control is
 *      disabled unless the user has `can_write_webhook_auth_method` (owner/admin),
 *      independent of general `can_edit_workflow` access. Regression coverage
 *      for the backend `update_trigger_auth_methods` permission tightening.
 */

import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { act } from 'react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import type * as Y from 'yjs';

import { WebhookConfigureStep } from '../../../../../js/collaborative-editor/components/inspector/trigger/WebhookConfigureStep';
import type { WorkflowStoreInstance } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import { createWorkflowStore } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import type { WebhookAuthMethod } from '../../../../../js/collaborative-editor/types/sessionContext';
import type { Workflow } from '../../../../../js/collaborative-editor/types/workflow';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
  createMockChannelPushOk,
} from '../../../__helpers__/channelMocks';
import { createTriggerTestHarness } from '../../../__helpers__/triggerInspectorHelpers';
import { createWorkflowYDoc } from '../../../__helpers__/workflowFactory';

function createConnectedWorkflowStore(ydoc: Y.Doc): WorkflowStoreInstance {
  const store = createWorkflowStore();
  const channel = createMockPhoenixChannel();
  const provider = createMockPhoenixChannelProvider(channel);
  store.connect(ydoc, provider as never);
  return store;
}

// A connected workflow store for a saved, non-deleted workflow — so
// `useWorkflowReadOnly` (now read by WebhookConfigureStep) resolves to editable.
function makeReadyWorkflowStore(): WorkflowStoreInstance {
  const ydoc = createWorkflowYDoc({
    triggers: { [TRIGGER_ID]: { id: TRIGGER_ID, type: 'webhook' } },
  });
  const workflowMap = ydoc.getMap('workflow');
  workflowMap.set('id', 'workflow-1');
  workflowMap.set('name', 'ET EMR Facility 003');
  workflowMap.set('lock_version', 1);
  workflowMap.set('deleted_at', null);
  return createConnectedWorkflowStore(ydoc);
}

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

const TRIGGER_ID = '11111111-1111-4111-8111-111111111111';

const mockLiveViewActions = {
  pushEvent: vi.fn(),
  pushEventTo: vi.fn(),
  handleEvent: vi.fn(() => () => {}),
  navigate: vi.fn(),
};

function makeWebhookDraft(
  overrides: Partial<Workflow.Trigger> = {}
): Workflow.Trigger {
  return {
    id: TRIGGER_ID,
    type: 'webhook',
    enabled: true,
    has_auth_method: false,
    cron_expression: null,
    cron_cursor_job_id: null,
    custom_path: null,
    webhook_reply: 'before_start',
    webhook_response_config: null,
    ...overrides,
  } as Workflow.Trigger;
}

// ---------------------------------------------------------------------------
// Render helper — builds context via harness then renders the step directly.
// ---------------------------------------------------------------------------

interface SetupOptions {
  draft?: Workflow.Trigger;
  mergeDraft?: (updates: Partial<Workflow.Trigger>) => void;
  draftAuthMethodIds?: string[];
  setDraftAuthMethodIds?: (ids: string[]) => void;
  validationError?: string | null;
  initialExpand?: 'authentication' | 'response';
  /** Defaults to true; set false to simulate an editor without owner/admin rights. */
  canWriteWebhookAuthMethod?: boolean;
  /** Project-level auth methods available to attach. Defaults to none. */
  webhookAuthMethods?: WebhookAuthMethod[];
  /** Project on the session context, for the custom-path URL prefix. */
  project?: { id: string; name: string } | null;
  /** Whether the path is the one the trigger opened with. */
  pathUnchanged?: boolean;
  /** What the server answers when asked whether the path is free. */
  pathTaken?: boolean;
  /** False to leave the check unanswered, as a slow connection would. */
  pathAnswers?: boolean;
}

async function setup({
  draft = makeWebhookDraft(),
  mergeDraft = vi.fn(),
  draftAuthMethodIds = [],
  setDraftAuthMethodIds = vi.fn(),
  validationError = null,
  initialExpand,
  canWriteWebhookAuthMethod = true,
  webhookAuthMethods = [],
  project = null,
  pathUnchanged = false,
  pathTaken = false,
  pathAnswers = true,
}: SetupOptions = {}) {
  const { wrapper, sessionChannel } = await createTriggerTestHarness({
    canEdit: true,
    canWriteWebhookAuthMethod,
    webhookAuthMethods,
    project,
    workflowStore: makeReadyWorkflowStore(),
    liveViewActions: mockLiveViewActions,
  });

  sessionChannel.push = pathAnswers
    ? createMockChannelPushOk({ taken: pathTaken })
    : (vi.fn(() => ({
        receive: () => ({ receive: () => ({ receive: () => ({}) }) }),
      })) as never);

  const onClose = vi.fn();
  const onCancel = vi.fn();
  const onBack = vi.fn();
  const onFinish = vi.fn();

  const { container } = render(
    <WebhookConfigureStep
      draft={draft}
      pathUnchanged={pathUnchanged}
      mergeDraft={mergeDraft}
      draftAuthMethodIds={draftAuthMethodIds}
      setDraftAuthMethodIds={setDraftAuthMethodIds}
      validationError={validationError}
      initialExpand={initialExpand}
      onClose={onClose}
      onCancel={onCancel}
      onBack={onBack}
      onFinish={onFinish}
    />,
    { wrapper }
  );

  return {
    container,
    onClose,
    onCancel,
    onBack,
    onFinish,
    mergeDraft,
    setDraftAuthMethodIds,
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('WebhookConfigureStep', () => {
  beforeEach(() => {
    mockLiveViewActions.pushEvent.mockClear();
  });

  // 1. Accordion state
  describe('accordion sections', () => {
    test('Authentication starts collapsed and expands on click', async () => {
      await setup();

      // Collapsed: description text inside the auth body is not visible.
      expect(
        screen.queryByText(/Require requests to this webhook/i)
      ).not.toBeInTheDocument();

      await userEvent.click(
        screen.getByRole('button', { name: 'Authentication' })
      );

      expect(
        screen.getByText(/Require requests to this webhook/i)
      ).toBeInTheDocument();

      // Clicking again collapses it.
      await userEvent.click(
        screen.getByRole('button', { name: 'Authentication' })
      );
      expect(
        screen.queryByText(/Require requests to this webhook/i)
      ).not.toBeInTheDocument();
    });

    test('Response Options starts collapsed and expands on click (after_completion mode)', async () => {
      await setup({
        draft: makeWebhookDraft({ webhook_reply: 'after_completion' }),
      });

      // The disclosure button is present but the inputs are hidden.
      const responseBtn = screen.getByRole('button', {
        name: 'Response Options',
      });
      expect(screen.queryByLabelText('Success Code')).not.toBeInTheDocument();

      await userEvent.click(responseBtn);

      expect(screen.getByLabelText('Success Code')).toBeInTheDocument();
      expect(screen.getByLabelText('Error Code')).toBeInTheDocument();
    });

    test('initialExpand="authentication" opens the Authentication section on mount', async () => {
      await setup({ initialExpand: 'authentication' });

      // Should already be open — description body visible without any click.
      expect(
        screen.getByText(/Require requests to this webhook/i)
      ).toBeInTheDocument();
    });

    test('initialExpand="response" opens the Response Options section on mount (after_completion mode)', async () => {
      await setup({
        draft: makeWebhookDraft({ webhook_reply: 'after_completion' }),
        initialExpand: 'response',
      });

      // Code inputs are immediately visible without clicking.
      expect(screen.getByLabelText('Success Code')).toBeInTheDocument();
      expect(screen.getByLabelText('Error Code')).toBeInTheDocument();
    });
  });

  // 2. DOM event relay
  describe('close_webhook_auth_modal DOM event relay', () => {
    let reactRoot: HTMLElement;

    beforeEach(() => {
      // Replicate the element the source component looks for.
      reactRoot = document.createElement('div');
      reactRoot.id = 'collaborative-editor-react';
      document.body.appendChild(reactRoot);
    });

    afterEach(() => {
      document.body.removeChild(reactRoot);
    });

    test('dispatching close_webhook_auth_modal calls pushEvent with close_webhook_auth_modal_complete', async () => {
      await setup();

      act(() => {
        reactRoot.dispatchEvent(
          new Event('close_webhook_auth_modal', { bubbles: true })
        );
      });

      expect(mockLiveViewActions.pushEvent).toHaveBeenCalledWith(
        'close_webhook_auth_modal_complete',
        {}
      );
    });

    test('the listener is removed on unmount (no stale push after unmount)', async () => {
      const { unmount } = render(
        <WebhookConfigureStep
          draft={makeWebhookDraft()}
          pathUnchanged={false}
          mergeDraft={vi.fn()}
          draftAuthMethodIds={[]}
          setDraftAuthMethodIds={vi.fn()}
          validationError={null}
          onClose={vi.fn()}
          onCancel={vi.fn()}
          onBack={vi.fn()}
          onFinish={vi.fn()}
        />,
        {
          wrapper: (
            await createTriggerTestHarness({
              workflowStore: makeReadyWorkflowStore(),
              liveViewActions: mockLiveViewActions,
            })
          ).wrapper,
        }
      );

      unmount();
      mockLiveViewActions.pushEvent.mockClear();

      act(() => {
        reactRoot.dispatchEvent(
          new Event('close_webhook_auth_modal', { bubbles: true })
        );
      });

      expect(mockLiveViewActions.pushEvent).not.toHaveBeenCalled();
    });
  });

  // 3. Response Options code inputs
  describe('Response Options inputs', () => {
    test('code inputs are NOT rendered when webhook_reply is before_start', async () => {
      await setup({
        draft: makeWebhookDraft({ webhook_reply: 'before_start' }),
      });

      // The "Response Options" disclosure button should not exist at all.
      expect(
        screen.queryByRole('button', { name: 'Response Options' })
      ).not.toBeInTheDocument();
    });

    test('Success Code input calls mergeDraft with the parsed integer', async () => {
      const mergeDraft = vi.fn();
      await setup({
        draft: makeWebhookDraft({
          webhook_reply: 'after_completion',
          webhook_response_config: null,
        }),
        mergeDraft,
        initialExpand: 'response',
      });

      // Use fireEvent.change for number inputs to set the full value in one shot.
      fireEvent.change(screen.getByLabelText('Success Code'), {
        target: { value: '201' },
      });

      const call = mergeDraft.mock.calls[0] as [Partial<Workflow.Trigger>];
      expect(call[0].webhook_response_config?.success_code).toBe(201);
    });

    test('Error Code input calls mergeDraft with the parsed integer', async () => {
      const mergeDraft = vi.fn();
      await setup({
        draft: makeWebhookDraft({
          webhook_reply: 'after_completion',
          webhook_response_config: null,
        }),
        mergeDraft,
        initialExpand: 'response',
      });

      fireEvent.change(screen.getByLabelText('Error Code'), {
        target: { value: '500' },
      });

      const call = mergeDraft.mock.calls[0] as [Partial<Workflow.Trigger>];
      expect(call[0].webhook_response_config?.error_code).toBe(500);
    });

    test('clearing a code input calls mergeDraft with null (not NaN)', async () => {
      const mergeDraft = vi.fn();
      await setup({
        draft: makeWebhookDraft({
          webhook_reply: 'after_completion',
          webhook_response_config: { success_code: 200, error_code: 400 },
        }),
        mergeDraft,
        initialExpand: 'response',
      });

      // An empty string in a number input should produce null, not NaN.
      fireEvent.change(screen.getByLabelText('Success Code'), {
        target: { value: '' },
      });

      const call = mergeDraft.mock.calls[0] as [Partial<Workflow.Trigger>];
      expect(call[0].webhook_response_config?.success_code).toBeNull();
    });
  });

  // 4. Async-mode warning
  describe('async-mode warning', () => {
    test('shows the warning when after_completion + non-null response config', async () => {
      await setup({
        draft: makeWebhookDraft({
          webhook_reply: 'after_completion',
          webhook_response_config: { success_code: 201, error_code: null },
        }),
      });

      expect(
        screen.getByText(
          'Switching to async will clear your response configuration.'
        )
      ).toBeInTheDocument();
    });

    test('does NOT show the warning when after_completion but config is null', async () => {
      await setup({
        draft: makeWebhookDraft({
          webhook_reply: 'after_completion',
          webhook_response_config: null,
        }),
      });

      expect(
        screen.queryByText(
          'Switching to async will clear your response configuration.'
        )
      ).not.toBeInTheDocument();
    });

    test('does NOT show the warning for before_start', async () => {
      await setup({
        draft: makeWebhookDraft({ webhook_reply: 'before_start' }),
      });

      expect(
        screen.queryByText(
          'Switching to async will clear your response configuration.'
        )
      ).not.toBeInTheDocument();
    });
  });

  // 5. Auth-method permission gating
  describe('auth-method permission gating', () => {
    const method: WebhookAuthMethod = {
      id: '22222222-2222-4222-8222-222222222222',
      name: 'Basic auth method',
      auth_type: 'basic',
    };

    test('the auth-method picker is disabled for an editor lacking can_write_webhook_auth_method', async () => {
      await setup({
        initialExpand: 'authentication',
        canWriteWebhookAuthMethod: false,
        webhookAuthMethods: [method],
        draftAuthMethodIds: [method.id],
      });

      expect(
        screen.getByLabelText('Authentication credential 1')
      ).toBeDisabled();
    });

    test('the auth-method picker is enabled for an owner/admin with can_write_webhook_auth_method', async () => {
      await setup({
        initialExpand: 'authentication',
        canWriteWebhookAuthMethod: true,
        webhookAuthMethods: [method],
        draftAuthMethodIds: [method.id],
      });

      expect(
        screen.getByLabelText('Authentication credential 1')
      ).not.toBeDisabled();
    });
  });
});

describe('WebhookConfigureStep — custom URL path', () => {
  const PROJECT = {
    id: '33333333-3333-4333-8333-333333333333',
    name: 'ET EMR',
  };

  // The list is the resting state: with no custom URL you add one, with one
  // already set you ask to edit it.
  const pathField = () => {
    const add = screen.queryByRole('button', { name: 'Add custom URL' });

    fireEvent.click(
      add ?? screen.getByRole('button', { name: 'Edit custom URL' })
    );

    return screen.getByLabelText('Custom path');
  };
  test('suggests the workflow name', async () => {
    // Offered, not written: an empty field still keeps the generated URL.
    await setup({ project: PROJECT });

    expect(pathField()).toHaveAttribute('placeholder', 'et-emr-facility-003');
  });

  test('shows the current path', async () => {
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'facility-001' }),
      pathUnchanged: true,
    });

    expect(pathField()).toHaveValue('facility-001');
  });

  test('shows the full prefix, with only the path editable', async () => {
    // The row is edited in place, so there is room for the whole prefix and no
    // second copy of the URL anywhere.
    await setup({ project: PROJECT });

    fireEvent.click(screen.getByRole('button', { name: 'Add custom URL' }));

    expect(
      screen.getByText(`${window.location.origin}/i/${PROJECT.id}/`)
    ).toBeInTheDocument();
    expect(screen.getByLabelText('Custom path')).toHaveValue('');
  });

  test('the edit icon becomes a save icon while editing, and Enter does it too', async () => {
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'facility-001' }),
      pathUnchanged: true,
    });

    fireEvent.click(screen.getByRole('button', { name: 'Edit custom URL' }));
    expect(
      screen.getByRole('button', { name: 'Save custom URL' })
    ).toBeInTheDocument();

    fireEvent.keyDown(screen.getByLabelText('Custom path'), { key: 'Enter' });

    // Back to the resting row, which offers Edit again.
    expect(
      screen.getByRole('button', { name: 'Edit custom URL' })
    ).toBeInTheDocument();
  });

  test('will not leave the field while the path is refused', async () => {
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'a'.repeat(256) }),
      pathUnchanged: false,
    });

    fireEvent.click(screen.getByRole('button', { name: 'Edit custom URL' }));

    expect(
      screen.getByRole('button', { name: 'Save custom URL' })
    ).toBeDisabled();
  });

  test('Tab takes the suggestion when nothing is typed', async () => {
    const mergeDraft = vi.fn();
    await setup({ project: PROJECT, mergeDraft });

    fireEvent.click(screen.getByRole('button', { name: 'Add custom URL' }));
    fireEvent.keyDown(screen.getByLabelText('Custom path'), { key: 'Tab' });

    expect(mergeDraft).toHaveBeenCalledWith({
      custom_path: 'et-emr-facility-003',
    });
  });

  test('Tab still moves focus once something is typed', async () => {
    const mergeDraft = vi.fn();
    await setup({
      project: PROJECT,
      mergeDraft,
      draft: makeWebhookDraft({ custom_path: 'fac' }),
      pathUnchanged: false,
    });

    fireEvent.click(screen.getByRole('button', { name: 'Edit custom URL' }));
    mergeDraft.mockClear();
    fireEvent.keyDown(screen.getByLabelText('Custom path'), { key: 'Tab' });

    expect(mergeDraft).not.toHaveBeenCalled();
  });

  test('shows a custom row as soon as you start adding one', async () => {
    // The row has to exist while the path is still empty, or it appears and
    // disappears as you type and clear. It is muted and not copyable until the
    // path is something the lookup can match.
    await setup({ project: PROJECT });

    fireEvent.click(screen.getByRole('button', { name: 'Add custom URL' }));

    expect(screen.getByText('Custom')).toBeInTheDocument();
    expect(
      screen.getByRole('button', { name: 'Not a usable URL yet' })
    ).toBeDisabled();
  });

  test('lists the URLs, default included', async () => {
    // The list is what you act on here, and the default is always in it so it
    // is clear a custom URL adds an address rather than replacing one.
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'facility-001' }),
      pathUnchanged: true,
    });

    expect(
      screen.getByText(`${window.location.origin}/i/${PROJECT.id}/facility-001`)
    ).toBeInTheDocument();
    expect(screen.getByText('Default')).toBeInTheDocument();
    expect(screen.getByText('Custom')).toBeInTheDocument();
  });

  test('takes the path as typed, without rewriting it', async () => {
    // The field is the URL itself, so a character it will not accept is an
    // error to fix rather than something to silently correct.
    const mergeDraft = vi.fn();
    await setup({ project: PROJECT, mergeDraft });

    fireEvent.change(pathField(), { target: { value: 'ET EMR Facility 003' } });

    expect(mergeDraft).toHaveBeenCalledWith({
      custom_path: 'ET EMR Facility 003',
    });
  });

  test('says what is wrong instead of correcting it', async () => {
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'hello!' }),
      pathUnchanged: false,
    });

    expect(
      screen.getByText(/lowercase letters, numbers, hyphens and underscores/i)
    ).toBeInTheDocument();
  });

  test('clearing the field clears the path', async () => {
    const mergeDraft = vi.fn();
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'facility-001' }),
      pathUnchanged: true,
      mergeDraft,
    });

    fireEvent.change(pathField(), {
      target: { value: '' },
    });

    expect(mergeDraft).toHaveBeenCalledWith({ custom_path: null });
  });

  test('flags a path the server would reject', async () => {
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'orders/intake' }),
      pathUnchanged: false,
    });

    const input = pathField();

    expect(input).toHaveAttribute('aria-invalid', 'true');
    expect(
      screen.getByText(/lowercase letters, numbers, hyphens and underscores/i)
    ).toBeInTheDocument();
  });

  test('flags a legacy path when the trigger is becoming a webhook', async () => {
    // The step and the hook have to agree, or Finish refuses with nothing
    // marked wrong.
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'orders.v1' }),
      pathUnchanged: false,
    });

    expect(pathField()).toHaveAttribute('aria-invalid', 'true');
  });

  test('does not flag a legacy path the user has not changed', async () => {
    // Saving is allowed while the path is left alone.
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'orders.v1' }),
      pathUnchanged: true,
    });

    expect(pathField()).not.toHaveAttribute('aria-invalid');
  });

  test('flags it once the user changes it', async () => {
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'orders.v2' }),
      pathUnchanged: false,
    });

    expect(pathField()).toHaveAttribute('aria-invalid', 'true');
  });

  test('holds a name that derives to nothing instead of clearing', async () => {
    // Every character strips away. Storing null would read as "cleared".
    const mergeDraft = vi.fn();
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'facility-001' }),
      pathUnchanged: true,
      mergeDraft,
    });

    fireEvent.change(pathField(), {
      target: { value: '...' },
    });

    expect(mergeDraft).toHaveBeenCalledWith({ custom_path: '...' });
  });

  test('flags a name made only of unusable characters', async () => {
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: '...' }),
      pathUnchanged: false,
    });

    const input = pathField();

    expect(input).toHaveAttribute('aria-invalid', 'true');
    expect(
      screen.getByText(/lowercase letters, numbers, hyphens and underscores/i)
    ).toBeInTheDocument();
  });

  test('drops a server error once the path is edited', async () => {
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({
        custom_path: 'facility-002',
        errors: { custom_path: ['is already used by another workflow'] },
      }),
      pathUnchanged: false,
    });

    expect(screen.queryByText(/already used/i)).toBeNull();
  });

  test('says when a path is too long, not that the characters are wrong', async () => {
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'a'.repeat(256) }),
      pathUnchanged: false,
    });

    expect(screen.getByText(/255 characters or fewer/i)).toBeInTheDocument();
  });

  test('shows an error the server sent back for the path', async () => {
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({
        custom_path: 'facility-001',
        errors: {
          custom_path: ['is already used by another workflow in this project'],
        },
      }),
      pathUnchanged: true,
    });

    expect(
      screen.getByText(/already used by another workflow/i)
    ).toBeInTheDocument();
  });

  test('says nothing about a name that is free', async () => {
    const { container } = await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'facility-009' }),
      pathUnchanged: false,
    });

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /finish/i })).toBeEnabled();
    });

    expect(container.textContent).not.toMatch(/available/i);
  });

  test('leaves no empty line under a row with nothing to say', async () => {
    const { container } = await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'facility-009' }),
      pathUnchanged: true,
    });

    expect(
      [...container.querySelectorAll('p')].some(
        el => el.textContent?.trim() === ''
      )
    ).toBe(false);
  });

  test('offers a path still being edited as a URL to copy', async () => {
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'facility-009' }),
      pathUnchanged: false,
    });

    expect(
      screen.getByRole('button', { name: 'Copy Custom URL' })
    ).toBeInTheDocument();
  });

  test('offers the saved path as a URL to copy', async () => {
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'facility-009' }),
      pathUnchanged: true,
    });

    expect(
      screen.getByRole('button', { name: 'Copy Custom URL' })
    ).toBeInTheDocument();
  });

  test('will not let you finish before the name has been checked', async () => {
    // Letting it through is how the failure ends up on the panel this closes
    // to, which is the thing the check exists to prevent.
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'facility-009' }),
      pathUnchanged: false,
      pathAnswers: false,
    });

    expect(screen.getByRole('button', { name: /finish/i })).toBeDisabled();
  });

  test('asks before deleting, whatever state the path is in', async () => {
    const mergeDraft = vi.fn();
    await setup({
      project: PROJECT,
      mergeDraft,
      draft: makeWebhookDraft({ custom_path: 'facility-009' }),
      pathUnchanged: false,
    });

    fireEvent.click(screen.getByRole('button', { name: 'Delete custom URL' }));

    expect(
      screen.getByText(/anything posting to it will stop working/i)
    ).toBeInTheDocument();
    expect(mergeDraft).not.toHaveBeenCalled();
  });

  test('asks before deleting a URL that is live', async () => {
    const mergeDraft = vi.fn();
    await setup({
      project: PROJECT,
      mergeDraft,
      draft: makeWebhookDraft({ custom_path: 'facility-009' }),
      pathUnchanged: true,
    });

    fireEvent.click(screen.getByRole('button', { name: 'Delete custom URL' }));

    expect(
      screen.getByText(/anything posting to it will stop working/i)
    ).toBeInTheDocument();
    expect(mergeDraft).not.toHaveBeenCalled();
  });

  test('trims a pasted path the way the server does', async () => {
    // Otherwise a trailing space fails against a character you cannot see.
    const mergeDraft = vi.fn();
    await setup({ project: PROJECT, mergeDraft, pathUnchanged: false });

    fireEvent.click(screen.getByRole('button', { name: 'Add custom URL' }));
    fireEvent.change(screen.getByLabelText('Custom path'), {
      target: { value: '  orders  ' },
    });

    expect(mergeDraft).toHaveBeenCalledWith({ custom_path: 'orders' });
  });

  test('will not let you finish on a name in use', async () => {
    // Otherwise the wizard closes and the failure lands on a panel you have
    // already left, which is the thing the live check exists to prevent.
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'facility-009' }),
      pathUnchanged: false,
      pathTaken: true,
    });

    await screen.findByText(/already used by another workflow/i);
    expect(screen.getByRole('button', { name: /finish/i })).toBeDisabled();
  });

  test('lets you finish once the name is free', async () => {
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'facility-009' }),
      pathUnchanged: false,
    });

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /finish/i })).toBeEnabled();
    });
  });

  test('never offers a refused path as a URL to copy', async () => {
    // A refused duplicate is not this trigger's URL. Posting to it reaches
    // whichever workflow legitimately owns the name, so the row is visible but
    // must not be copyable.
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({
        custom_path: 'facility-001',
        errors: {
          custom_path: ['is already used by another workflow in this project'],
        },
      }),
      pathUnchanged: true,
    });

    expect(
      screen.getByRole('button', { name: /not a usable url/i })
    ).toBeDisabled();
    expect(
      screen.queryByRole('button', { name: 'Copy Custom URL' })
    ).not.toBeInTheDocument();
  });

  test('links the error to the field for screen readers', async () => {
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'orders/intake' }),
      pathUnchanged: false,
    });

    expect(pathField()).toHaveAttribute(
      'aria-describedby',
      'webhook-custom-path-error'
    );
  });

  test('flags a UUID typed as a path', async () => {
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({
        custom_path: '3fa85f64-5717-4562-b3fc-2c963f66afa6',
      }),
      pathUnchanged: false,
    });

    const input = pathField();

    expect(input).toHaveAttribute('aria-invalid', 'true');
    expect(screen.getByText(/cannot be used as a path/i)).toBeInTheDocument();
  });

  test('accepts a sixteen-character name', async () => {
    await setup({
      project: PROJECT,
      draft: makeWebhookDraft({ custom_path: 'orders_intake_v1' }),
      pathUnchanged: false,
    });

    const input = pathField();

    expect(input).not.toHaveAttribute('aria-invalid');
  });
});
