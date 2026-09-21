/** Opens a run at the content it executed, asking first if that loses edits. */

import { useCallback } from 'react';

import { useURLState } from '#/react/lib/use-url-state';

import { AS_RUN_PARAM, CLEAR_PINNED_VIEW } from '../lib/pinnedView';

import { useDiscardGuard } from './useDiscardGuard';

export function useViewAsExecuted() {
  const { updateSearchParams } = useURLState();
  const { guard, ...prompt } = useDiscardGuard();

  const viewAsExecuted = useCallback(
    (runId: string, onProceed?: () => void) => {
      guard(() => {
        onProceed?.();
        updateSearchParams({
          ...CLEAR_PINNED_VIEW,
          [AS_RUN_PARAM]: runId,
          run: runId,
        });
      });
    },
    [guard, updateSearchParams]
  );

  return { viewAsExecuted, prompt };
}
