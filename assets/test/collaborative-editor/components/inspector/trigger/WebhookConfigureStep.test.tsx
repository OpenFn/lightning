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
 */

import { fireEvent, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { act } from 'react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import type * as Y from 'yjs';

import { WebhookConfigureStep } from '../../../../../js/collaborative-editor/components/inspector/trigger/WebhookConfigureStep';
import type { WorkflowStoreInstance } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import { createWorkflowStore } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Workflow } from '../../../../../js/collaborative-editor/types/workflow';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
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
    kafka_configuration: null,
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
}

async function setup({
  draft = makeWebhookDraft(),
  mergeDraft = vi.fn(),
  draftAuthMethodIds = [],
  setDraftAuthMethodIds = vi.fn(),
  validationError = null,
  initialExpand,
}: SetupOptions = {}) {
  const { wrapper } = await createTriggerTestHarness({
    canEdit: true,
    workflowStore: makeReadyWorkflowStore(),
    liveViewActions: mockLiveViewActions,
  });

  const onClose = vi.fn();
  const onCancel = vi.fn();
  const onBack = vi.fn();
  const onFinish = vi.fn();

  render(
    <WebhookConfigureStep
      draft={draft}
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
});
