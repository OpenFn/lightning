import { useEffect, useState } from 'react';

import { isValidCustomPath } from '#/collaborative-editor/types/trigger';

import { channelRequest } from '../../../hooks/useChannel';
import { useSession } from '../../../hooks/useSession';

export interface CustomPathCheck {
  /** The server says another webhook in the project already answers here. */
  taken: boolean;
  /** Waiting on an answer. A request that failed is not pending, it is over. */
  pending: boolean;
  /** Pending, and long enough that it is worth saying so. */
  showPending: boolean;
}

const NOT_ASKED: CustomPathCheck = {
  taken: false,
  pending: false,
  showPending: false,
};

const DEBOUNCE_MS = 300;

// Measured from the request. Long enough that a quick answer never flashes a
// spinner, short enough that a slow one does not look like the field has
// stopped responding.
const PENDING_REVEAL_MS = 400;

/**
 * Whether another webhook in the project already answers on this path.
 *
 * Uniqueness is only knowable on the server, and without this you find out by
 * saving: the wizard closes, the save fails, and the reason lands on a panel
 * you have already left.
 *
 * Advisory only. The partial unique index is what guarantees it, and a save can
 * still lose the race, so the error the server returns on save stays.
 */
export function useCustomPathTaken(
  path: string,
  triggerId: string
): CustomPathCheck {
  const { provider } = useSession();
  const channel = provider?.channel;
  const [check, setCheck] = useState<CustomPathCheck>(NOT_ASKED);

  useEffect(() => {
    if (!channel || !isValidCustomPath(path)) {
      setCheck(NOT_ASKED);
      return;
    }

    let current = true;
    let reveal: ReturnType<typeof setTimeout> | undefined;

    // The previous answer was about the previous path. Carrying it over tells
    // someone who has just fixed a duplicate that the name is still taken.
    setCheck({ taken: false, pending: true, showPending: false });

    const timer = setTimeout(() => {
      // Started with the request and cancelled by it, so an answer that has
      // already landed is never overwritten by a late reveal.
      reveal = setTimeout(() => {
        if (current) {
          setCheck({ taken: false, pending: true, showPending: true });
        }
      }, PENDING_REVEAL_MS);

      void channelRequest<{ taken: boolean }>(channel, 'check_custom_path', {
        custom_path: path,
        trigger_id: triggerId,
      })
        .then(response => {
          clearTimeout(reveal);
          if (current) {
            setCheck({
              taken: response.taken,
              pending: false,
              showPending: false,
            });
          }
          return response;
        })
        .catch(() => {
          // Not an answer, so stop blocking and let the server have the say on
          // save. Claiming a name is free because a request failed is worse.
          clearTimeout(reveal);
          if (current) setCheck(NOT_ASKED);
        });
    }, DEBOUNCE_MS);

    return () => {
      current = false;
      clearTimeout(reveal);
      clearTimeout(timer);
    };
  }, [channel, path, triggerId]);

  return check;
}
