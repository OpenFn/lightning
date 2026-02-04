import { useCallback, useEffect, useRef } from 'react';
import type { RefObject } from 'react';

import type { MonacoHandle } from '../components/CollaborativeMonaco';
import type { AIAssistantStoreInstance } from '../stores/createAIAssistantStore';

import type { AIModeResult } from './useAIMode';

/**
 * Hook to manage diff preview lifecycle for AI Assistant Panel
 *
 * Handles clearing Monaco diffs when context changes:
 * - Panel close: Clear diff and close panel
 * - Session list: Clear diff and return to session list
 * - Version change: Clear diff when switching to pinned version
 * - Job change: Clear diff when switching between jobs
 *
 * Accepts raw dependencies (functions and stores) instead of callbacks,
 * creating the callbacks internally for cleaner usage.
 */
export function useAIPanelDiffManager({
  isOpen,
  previewingMessageId,
  setPreviewingMessageId,
  monacoRef,
  currentVersion,
  aiMode,
  closeAIAssistantPanel,
  aiStore,
  updateSearchParams,
}: {
  isOpen: boolean;
  previewingMessageId: string | null;
  setPreviewingMessageId: (id: string | null) => void;
  monacoRef: RefObject<MonacoHandle> | null;
  currentVersion: string | undefined;
  aiMode: AIModeResult | null;
  closeAIAssistantPanel: () => void;
  aiStore: AIAssistantStoreInstance;
  updateSearchParams: (updates: Record<string, string | null>) => void;
}) {
  const previousVersionRef = useRef(currentVersion);
  const previousJobIdRef = useRef<string | null>(null);

  // Helper to clear diff
  const clearDiff = useCallback(() => {
    const monaco = monacoRef?.current;
    if (previewingMessageId && monaco) {
      monaco.clearDiff();
      setPreviewingMessageId(null);
    }
  }, [previewingMessageId, setPreviewingMessageId, monacoRef]);

  // Close handler - clears diff and closes panel
  const handleClosePanel = useCallback(() => {
    clearDiff();
    closeAIAssistantPanel();
  }, [clearDiff, closeAIAssistantPanel]);

  // Show sessions handler - clears diff and shows session list
  const handleShowSessions = useCallback(() => {
    clearDiff();
    // Clear AI session and reinitialize context
    aiStore.clearSession();
    aiStore._clearSessionList();
    if (aiMode) {
      aiStore._initializeContext(aiMode.mode, aiMode.context);
    }
    // Clear URL parameters
    updateSearchParams({
      'w-chat': null,
      'j-chat': null,
    });
  }, [clearDiff, aiStore, aiMode, updateSearchParams]);

  // Version change effect - clear diff when version changes
  useEffect(() => {
    // Only act if version actually changed (not on initial mount)
    if (previousVersionRef.current !== currentVersion) {
      const monaco = monacoRef?.current;
      // Clear diff if one is being previewed
      if (previewingMessageId && monaco) {
        monaco.clearDiff();
        setPreviewingMessageId(null);
      }

      // Close AI panel and clear session if switching TO a pinned version
      const isPinnedVersion =
        currentVersion !== undefined && currentVersion !== null;
      if (isPinnedVersion && isOpen) {
        closeAIAssistantPanel();
        aiStore.clearSession();
        updateSearchParams({
          'w-chat': null,
          'j-chat': null,
        });
      }
    }

    previousVersionRef.current = currentVersion;
  }, [
    currentVersion,
    previewingMessageId,
    monacoRef,
    isOpen,
    closeAIAssistantPanel,
    aiStore,
    updateSearchParams,
    setPreviewingMessageId,
  ]);

  // Job change effect - clear diff when switching jobs
  useEffect(() => {
    // Only track job changes when in job_code mode
    if (!aiMode || aiMode.mode !== 'job_code') {
      previousJobIdRef.current = null;
      return;
    }

    const context = aiMode.context as { job_id?: string };
    const currentJobId = context.job_id;

    // Safety check: if no job_id, reset tracking and return
    if (!currentJobId) {
      previousJobIdRef.current = null;
      return;
    }

    // Detect actual job change (not initial mount)
    if (
      previousJobIdRef.current !== null &&
      previousJobIdRef.current !== currentJobId
    ) {
      const monaco = monacoRef?.current;

      // Clear any active diff preview when job changes
      if (previewingMessageId && monaco) {
        monaco.clearDiff();
        setPreviewingMessageId(null);
      }
    }

    // Update tracked job ID
    previousJobIdRef.current = currentJobId;
  }, [aiMode, previewingMessageId, monacoRef, setPreviewingMessageId]);

  return {
    handleClosePanel,
    handleShowSessions,
  };
}
