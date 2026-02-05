import { useRef, useEffect } from 'react';

import type { Session, WorkflowTemplateContext } from '../types/ai-assistant';

import type { AIModeResult } from './useAIMode';

/**
 * Automatically previews AI-generated code when a new message arrives.
 *
 * **What it does:**
 * - Watches for new assistant messages with code
 * - Only auto-previews if current user authored the triggering user message
 * - Skips auto-preview on session mount (only for new messages)
 * - Prevents duplicate previews of the same message
 *
 * **Why separate hook:**
 * - Testable in isolation
 * - Reusable pattern (mirrors workflow auto-apply)
 * - Keeps AIAssistantPanelWrapper cleaner
 * - Encapsulates auto-preview logic for maintainability
 *
 * **Pattern:**
 * This mirrors the workflow auto-apply pattern where only the user who
 * triggered the AI action sees automatic updates. Other collaborators
 * viewing the same session won't see auto-preview for messages they
 * didn't author.
 *
 * @param aiMode - Current AI mode (must be 'job_code')
 * @param session - Current chat session with messages
 * @param currentUserId - ID of currently logged-in user
 * @param onPreview - Callback to show preview (receives code and messageId)
 */
export function useAutoPreview({
  aiMode,
  session,
  currentUserId,
  onPreview,
}: {
  aiMode: AIModeResult | null;
  session: Session | null;
  currentUserId: string | undefined;
  onPreview: (code: string, messageId: string) => void;
}) {
  const stateRef = useRef({
    hasLoadedSession: false,
    lastAutoPreviewedMessageId: null as string | null,
    sessionId: null as string | null,
  });

  useEffect(() => {
    // Reset state only when switching between different sessions
    if (
      session?.id &&
      stateRef.current.sessionId &&
      session.id !== stateRef.current.sessionId
    ) {
      // Switching between different existing sessions - full reset
      stateRef.current = {
        hasLoadedSession: false,
        lastAutoPreviewedMessageId: null,
        sessionId: session.id,
      };
    } else if (session?.id && !stateRef.current.sessionId) {
      // Session created for first time - track the session ID
      // If session has NO assistant code messages, mark as loaded immediately
      // If session HAS assistant code messages, keep hasLoadedSession false (skip old messages on mount)
      const hasCodeMessages =
        session.messages?.some(m => m.role === 'assistant' && m.code) ?? false;
      stateRef.current.sessionId = session.id;
      if (!hasCodeMessages) {
        stateRef.current.hasLoadedSession = true;
      }
    } else if (!session?.id && stateRef.current.sessionId) {
      // Session cleared - reset everything
      stateRef.current = {
        hasLoadedSession: false,
        lastAutoPreviewedMessageId: null,
        sessionId: null,
      };
    }

    // Only operate in job_code mode AND when session is job_code type
    // This prevents auto-previewing workflow YAML when user clicks into a job
    // while viewing a workflow_template session
    if (!aiMode || !(aiMode.context as WorkflowTemplateContext)?.job_ctx) {
      return;
    }
    if (!session?.messages) return;

    // Find latest assistant message with code
    // Sort by inserted_at descending to get most recent first
    const latestCodeMessage = session.messages
      .filter(m => m.role === 'assistant' && m.code)
      .sort(
        (a, b) =>
          new Date(b.inserted_at).getTime() - new Date(a.inserted_at).getTime()
      )[0];

    if (!latestCodeMessage || !latestCodeMessage.job_id) {
      return;
    }

    // Skip if we've already auto-previewed this message
    if (stateRef.current.lastAutoPreviewedMessageId === latestCodeMessage.id) {
      return;
    }

    // Only auto-preview if session has loaded (not on mount)
    // This prevents preview flash when opening AI panel with existing messages
    if (!stateRef.current.hasLoadedSession) {
      stateRef.current.hasLoadedSession = true;
      // Mark existing message as "seen" so it won't be previewed on subsequent renders
      stateRef.current.lastAutoPreviewedMessageId = latestCodeMessage.id;
      return;
    }

    // Only auto-preview if current user authored the triggering message
    // Find the user message that triggered this assistant response
    const messageIndex = session.messages.indexOf(latestCodeMessage);
    const previousUserMessage = session.messages
      .slice(0, messageIndex)
      .reverse()
      .find(m => m.role === 'user');

    if (!previousUserMessage) {
      return;
    }

    // Check if the previous user message was sent by the current user
    if (previousUserMessage.user_id !== currentUserId) {
      // Different user authored the triggering message - don't auto-preview
      return;
    }

    // Auto-preview - Only for the message author
    onPreview(latestCodeMessage.code!, latestCodeMessage.id);
    stateRef.current.lastAutoPreviewedMessageId = latestCodeMessage.id;
  }, [aiMode, session, currentUserId, onPreview]);
}
