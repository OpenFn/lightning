/**
 * Tests for channelRequest — the promise wrapper around a Phoenix push.
 *
 * The load-bearing property here is that every reply settles the promise. The
 * error branch builds a ChannelRequestError as the argument to `reject`, so
 * anything that throws while constructing it pre-empts the rejection and leaves
 * the caller awaiting forever. Several handlers reply `{reason: "..."}` with no
 * `errors` map, which is exactly that case.
 */

import type { Channel } from 'phoenix';
import { describe, expect, it } from 'vitest';

import { channelRequest } from '../../../js/collaborative-editor/hooks/useChannel';
import { ChannelRequestError } from '../../../js/collaborative-editor/lib/errors';

/**
 * A channel whose push replies with `status` and `response` on the next tick.
 * Deliberately minimal: this suite is about how channelRequest handles a reply,
 * not about Phoenix's own dispatch.
 */
function channelReplying(status: string, response: unknown): Channel {
  return {
    push: () => {
      const handlers = new Map<string, (payload?: unknown) => void>();
      let scheduled = false;
      const push = {
        receive(s: string, cb: (payload?: unknown) => void) {
          handlers.set(s, cb);
          // One reply, delivered once — Phoenix dispatches a reply a single
          // time, not once per `receive` call. Scheduling on the first call is
          // enough: the chained calls are synchronous, so every handler is
          // registered by the time the microtask runs.
          if (!scheduled) {
            scheduled = true;
            queueMicrotask(() => {
              handlers.get(status)?.(response);
            });
          }
          return push;
        },
      };
      return push;
    },
  } as unknown as Channel;
}

/**
 * Resolves to 'pending' if the promise has not settled by the time the macrotask
 * queue drains. Without this a regression hangs the runner until the suite
 * timeout instead of failing with a readable message.
 */
async function settlesWithin(promise: Promise<unknown>) {
  const pending = Symbol('pending');
  const outcome = await Promise.race([
    promise.then(
      value => ({ status: 'resolved' as const, value }),
      (error: unknown) => ({ status: 'rejected' as const, error })
    ),
    new Promise<typeof pending>(resolve => {
      setTimeout(() => {
        resolve(pending);
      }, 50);
    }),
  ]);

  return outcome === pending ? { status: 'pending' as const } : outcome;
}

describe('channelRequest', () => {
  it('resolves with the payload on ok', async () => {
    const outcome = await settlesWithin(
      channelRequest(channelReplying('ok', { templates: [] }), 'list', {})
    );

    expect(outcome).toEqual({
      status: 'resolved',
      value: { templates: [] },
    });
  });

  it('rejects with a ChannelRequestError on a standard error reply', async () => {
    const outcome = await settlesWithin(
      channelRequest(
        channelReplying('error', {
          type: 'unauthorized',
          errors: { base: ['This workflow has been deleted'] },
        }),
        'save_workflow',
        {}
      )
    );

    expect(outcome.status).toBe('rejected');
    const error = (outcome as { error: unknown }).error;
    expect(error).toBeInstanceOf(ChannelRequestError);
    expect((error as ChannelRequestError).message).toBe(
      'This workflow has been deleted'
    );
  });

  it('rejects — rather than hanging — when the reply has no errors map', async () => {
    // workflow_channel.ex replies `{:error, %{reason: "trigger not found"}}` from
    // update_trigger_auth_methods. A user without write_webhook_auth_method
    // pressing Save in the webhook auth panel takes this branch; before the
    // formatter tolerated a missing map, commitAuthMethods awaited forever with
    // no toast and a stuck spinner.
    const outcome = await settlesWithin(
      channelRequest(
        channelReplying('error', { reason: 'trigger not found' }),
        'update_trigger_auth_methods',
        {}
      )
    );

    expect(outcome.status).toBe('rejected');
    const error = (outcome as { error: unknown }).error;
    expect(error).toBeInstanceOf(ChannelRequestError);
    // The reply's own wording reaches the caller, rather than a generic fallback.
    expect((error as ChannelRequestError).message).toBe('trigger not found');
    // Consumers read `.errors` unconditionally, so it must still be an object.
    expect((error as ChannelRequestError).errors).toEqual({});
  });

  it('rejects on timeout', async () => {
    const outcome = await settlesWithin(
      channelRequest(channelReplying('timeout', undefined), 'save_workflow', {})
    );

    expect(outcome.status).toBe('rejected');
    expect((outcome as { error: Error }).error.message).toBe(
      'Request timed out'
    );
  });
});
