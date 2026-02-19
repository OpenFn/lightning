import { useEffect, useMemo, useRef } from 'react';

import type { AIAssistantStoreInstance } from '../stores/createAIAssistantStore';

import type { AIModeResult } from './useAIMode';

/**
 * Hook to manage URL parameter synchronization for AI Assistant Panel
 *
 * Handles bidirectional sync between panel state and URL params:
 * - Panel open/close: Syncs to ?chat=true param
 * - Session ID: Syncs to ?w-chat or ?j-chat based on mode
 * - Re-entrancy protection: Prevents infinite loops during URL updates
 *
 * Accepts raw dependencies (functions and stores) instead of callbacks,
 * creating the effects internally for cleaner usage.
 */
export function useAIPanelURLSync({
  isOpen,
  isNewWorkflow,
  sessionId,
  aiMode,
  aiStore,
  updateSearchParams,
  params,
}: {
  isOpen: boolean;
  isNewWorkflow: boolean;
  sessionId: string | null;
  aiMode: AIModeResult | null;
  aiStore: AIAssistantStoreInstance;
  updateSearchParams: (updates: Record<string, string | null>) => void;
  params: Record<string, string | undefined>;
}) {
  /**
   * isSyncingRef prevents re-entrant URL updates during panel state changes.
   *
   * Pattern explanation:
   * - When we update URL params, React re-renders with new searchParams
   * - This could trigger another URL update, creating an infinite loop
   * - We use a ref to track ongoing sync operations
   * - setTimeout(..., 0) breaks out of the current execution context,
   *   allowing the URL update to complete before we clear the flag
   *
   * This is a defensive pattern for synchronizing state with URL parameters.
   */
  const isSyncingRef = useRef(false);

  // Sync panel open/close to URL
  useEffect(() => {
    if (isSyncingRef.current) return;

    isSyncingRef.current = true;

    if (isOpen) {
      updateSearchParams({
        chat: 'true',
      });
    } else {
      // When closing, clear chat param and session params
      updateSearchParams({
        chat: null,
        ...(isNewWorkflow
          ? {
              job: null,
              trigger: null,
              edge: null,
            }
          : {}),
        'w-chat': null,
        'j-chat': null,
      });
    }

    setTimeout(() => {
      isSyncingRef.current = false;
    }, 0);
  }, [isOpen, updateSearchParams]);

  // Extract session ID from URL based on mode
  const sessionIdFromURL = useMemo(() => {
    if (!aiMode) return null;

    const paramName = aiMode.mode === 'workflow_template' ? 'w-chat' : 'j-chat';
    const sessionId = params[paramName];

    // Normalize undefined to null for consistency
    return sessionId ?? null;
  }, [aiMode, params]);

  // Sync session ID to URL
  useEffect(() => {
    // Don't sync session ID to URL when panel is closed
    if (!isOpen) return;
    if (!sessionId || !aiMode) return;

    const state = aiStore.getSnapshot();
    const sessionType = state.sessionType;

    // CRITICAL: Only sync to URL if session type matches current mode
    // This prevents syncing a workflow session ID to job mode URL (or vice versa)
    if (sessionType !== aiMode.mode) {
      return;
    }

    const currentParamName =
      aiMode.mode === 'workflow_template' ? 'w-chat' : 'j-chat';
    const otherParamName =
      aiMode.mode === 'workflow_template' ? 'j-chat' : 'w-chat';
    const currentValue = params[currentParamName];

    if (currentValue !== sessionId) {
      updateSearchParams({
        [currentParamName]: sessionId,
        [otherParamName]: null, // Clear the other mode's session
      });
    }
  }, [sessionId, aiMode, params, updateSearchParams, aiStore, isOpen]);

  return {
    sessionIdFromURL,
  };
}
