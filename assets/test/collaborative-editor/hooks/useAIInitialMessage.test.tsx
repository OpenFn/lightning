/**
 * useAIInitialMessage - Tests for auto-sending initial AI messages
 *
 * Tests the hook that handles auto-sending messages when users trigger AI
 * Assistant from template search with a pre-filled query.
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { renderHook, act } from '@testing-library/react';

import { useAIInitialMessage } from '../../../js/collaborative-editor/hooks/useAIInitialMessage';
import type { AIModeResult } from '../../../js/collaborative-editor/hooks/useAIMode';
import type { AIAssistantStoreInstance } from '../../../js/collaborative-editor/stores/createAIAssistantStore';

// Mock the workflow serialization utility
vi.mock('../../../js/collaborative-editor/utils/workflowSerialization', () => ({
  serializeWorkflowToYAML: vi.fn(() => 'name: Test Workflow\njobs: []'),
}));

describe('useAIInitialMessage', () => {
  let mockAiStore: Partial<AIAssistantStoreInstance>;
  let mockUpdateSearchParams: ReturnType<typeof vi.fn>;
  let mockClearInitialMessage: ReturnType<typeof vi.fn>;

  const defaultWorkflowData = {
    workflow: { id: 'workflow-123', name: 'Test Workflow' },
    jobs: [
      {
        id: 'job-1',
        name: 'Job 1',
        adaptor: '@openfn/language-http',
        body: 'fn()',
      },
    ],
    triggers: [{ id: 'trigger-1', type: 'webhook' }],
    edges: [],
    positions: {},
  };

  const workflowTemplateMode: AIModeResult = {
    mode: 'workflow_template',
    context: { project_id: 'project-123' },
    storageKey: 'ai-workflow-workflow-123',
  };

  const jobCodeMode: AIModeResult = {
    mode: 'job_code',
    context: { job_id: 'job-1', attach_code: false, attach_logs: false },
    storageKey: 'ai-job-job-1',
  };

  beforeEach(() => {
    vi.clearAllMocks();

    mockAiStore = {
      connect: vi.fn(),
      setMessageSending: vi.fn(),
    };

    mockUpdateSearchParams = vi.fn();
    mockClearInitialMessage = vi.fn();
  });

  it('does nothing when initialMessage is null', () => {
    renderHook(() =>
      useAIInitialMessage({
        initialMessage: null,
        aiMode: workflowTemplateMode,
        sessionId: null,
        connectionState: 'disconnected',
        isAIAssistantPanelOpen: true,
        aiStore: mockAiStore as AIAssistantStoreInstance,
        workflowData: defaultWorkflowData,
        updateSearchParams: mockUpdateSearchParams,
        clearAIAssistantInitialMessage: mockClearInitialMessage,
      })
    );

    expect(mockAiStore.connect).not.toHaveBeenCalled();
  });

  it('does nothing when aiMode is null', () => {
    renderHook(() =>
      useAIInitialMessage({
        initialMessage: 'Create a workflow',
        aiMode: null,
        sessionId: null,
        connectionState: 'disconnected',
        isAIAssistantPanelOpen: true,
        aiStore: mockAiStore as AIAssistantStoreInstance,
        workflowData: defaultWorkflowData,
        updateSearchParams: mockUpdateSearchParams,
        clearAIAssistantInitialMessage: mockClearInitialMessage,
      })
    );

    expect(mockAiStore.connect).not.toHaveBeenCalled();
  });

  it('does nothing when session already exists', () => {
    renderHook(() =>
      useAIInitialMessage({
        initialMessage: 'Create a workflow',
        aiMode: workflowTemplateMode,
        sessionId: 'existing-session',
        connectionState: 'disconnected',
        isAIAssistantPanelOpen: true,
        aiStore: mockAiStore as AIAssistantStoreInstance,
        workflowData: defaultWorkflowData,
        updateSearchParams: mockUpdateSearchParams,
        clearAIAssistantInitialMessage: mockClearInitialMessage,
      })
    );

    expect(mockAiStore.connect).not.toHaveBeenCalled();
  });

  it('does nothing when already connected', () => {
    renderHook(() =>
      useAIInitialMessage({
        initialMessage: 'Create a workflow',
        aiMode: workflowTemplateMode,
        sessionId: null,
        connectionState: 'connected',
        isAIAssistantPanelOpen: true,
        aiStore: mockAiStore as AIAssistantStoreInstance,
        workflowData: defaultWorkflowData,
        updateSearchParams: mockUpdateSearchParams,
        clearAIAssistantInitialMessage: mockClearInitialMessage,
      })
    );

    expect(mockAiStore.connect).not.toHaveBeenCalled();
  });

  it('does nothing when panel is closed', () => {
    renderHook(() =>
      useAIInitialMessage({
        initialMessage: 'Create a workflow',
        aiMode: workflowTemplateMode,
        sessionId: null,
        connectionState: 'disconnected',
        isAIAssistantPanelOpen: false,
        aiStore: mockAiStore as AIAssistantStoreInstance,
        workflowData: defaultWorkflowData,
        updateSearchParams: mockUpdateSearchParams,
        clearAIAssistantInitialMessage: mockClearInitialMessage,
      })
    );

    expect(mockAiStore.connect).not.toHaveBeenCalled();
  });

  it('sends initial message in workflow_template mode', () => {
    renderHook(() =>
      useAIInitialMessage({
        initialMessage: 'Create a workflow for DHIS2',
        aiMode: workflowTemplateMode,
        sessionId: null,
        connectionState: 'disconnected',
        isAIAssistantPanelOpen: true,
        aiStore: mockAiStore as AIAssistantStoreInstance,
        workflowData: defaultWorkflowData,
        updateSearchParams: mockUpdateSearchParams,
        clearAIAssistantInitialMessage: mockClearInitialMessage,
      })
    );

    expect(mockAiStore.connect).toHaveBeenCalledWith(
      'workflow_template',
      expect.objectContaining({
        project_id: 'project-123',
        content: 'Create a workflow for DHIS2',
        code: expect.any(String),
      })
    );
    expect(mockUpdateSearchParams).toHaveBeenCalledWith({
      'w-chat': 'new',
      'j-chat': null,
    });
    expect(mockAiStore.setMessageSending).toHaveBeenCalled();
    expect(mockClearInitialMessage).toHaveBeenCalled();
  });

  it('sends initial message in job_code mode', () => {
    renderHook(() =>
      useAIInitialMessage({
        initialMessage: 'Help me with this job',
        aiMode: jobCodeMode,
        sessionId: null,
        connectionState: 'disconnected',
        isAIAssistantPanelOpen: true,
        aiStore: mockAiStore as AIAssistantStoreInstance,
        workflowData: defaultWorkflowData,
        updateSearchParams: mockUpdateSearchParams,
        clearAIAssistantInitialMessage: mockClearInitialMessage,
      })
    );

    expect(mockAiStore.connect).toHaveBeenCalledWith(
      'job_code',
      expect.objectContaining({
        job_id: 'job-1',
        content: 'Help me with this job',
      })
    );
    expect(mockUpdateSearchParams).toHaveBeenCalledWith({
      'j-chat': 'new',
      'w-chat': null,
    });
    expect(mockAiStore.setMessageSending).toHaveBeenCalled();
    expect(mockClearInitialMessage).toHaveBeenCalled();
  });

  it('only sends message once per mount', () => {
    const { rerender } = renderHook(() =>
      useAIInitialMessage({
        initialMessage: 'Create a workflow',
        aiMode: workflowTemplateMode,
        sessionId: null,
        connectionState: 'disconnected',
        isAIAssistantPanelOpen: true,
        aiStore: mockAiStore as AIAssistantStoreInstance,
        workflowData: defaultWorkflowData,
        updateSearchParams: mockUpdateSearchParams,
        clearAIAssistantInitialMessage: mockClearInitialMessage,
      })
    );

    expect(mockAiStore.connect).toHaveBeenCalledTimes(1);

    // Re-render with same props
    rerender();
    rerender();

    // Should still only be called once
    expect(mockAiStore.connect).toHaveBeenCalledTimes(1);
  });

  it('resets sent flag when panel closes', () => {
    const { rerender } = renderHook(
      ({ isOpen }) =>
        useAIInitialMessage({
          initialMessage: 'Create a workflow',
          aiMode: workflowTemplateMode,
          sessionId: null,
          connectionState: 'disconnected',
          isAIAssistantPanelOpen: isOpen,
          aiStore: mockAiStore as AIAssistantStoreInstance,
          workflowData: defaultWorkflowData,
          updateSearchParams: mockUpdateSearchParams,
          clearAIAssistantInitialMessage: mockClearInitialMessage,
        }),
      { initialProps: { isOpen: true } }
    );

    expect(mockAiStore.connect).toHaveBeenCalledTimes(1);

    // Close panel
    rerender({ isOpen: false });

    // Reset mocks
    vi.clearAllMocks();

    // Re-open panel - should send again
    rerender({ isOpen: true });

    expect(mockAiStore.connect).toHaveBeenCalledTimes(1);
  });

  it('resets sent flag when initialMessage is cleared', () => {
    const { rerender } = renderHook(
      ({ message }) =>
        useAIInitialMessage({
          initialMessage: message,
          aiMode: workflowTemplateMode,
          sessionId: null,
          connectionState: 'disconnected',
          isAIAssistantPanelOpen: true,
          aiStore: mockAiStore as AIAssistantStoreInstance,
          workflowData: defaultWorkflowData,
          updateSearchParams: mockUpdateSearchParams,
          clearAIAssistantInitialMessage: mockClearInitialMessage,
        }),
      { initialProps: { message: 'First message' as string | null } }
    );

    expect(mockAiStore.connect).toHaveBeenCalledTimes(1);

    // Clear message
    rerender({ message: null });

    // Reset mocks
    vi.clearAllMocks();

    // Set new message - should send again
    rerender({ message: 'Second message' });

    expect(mockAiStore.connect).toHaveBeenCalledTimes(1);
    expect(mockAiStore.connect).toHaveBeenCalledWith(
      'workflow_template',
      expect.objectContaining({
        content: 'Second message',
      })
    );
  });

  it('handles empty workflow gracefully', () => {
    const emptyWorkflowData = {
      workflow: null,
      jobs: [],
      triggers: [],
      edges: [],
      positions: {},
    };

    renderHook(() =>
      useAIInitialMessage({
        initialMessage: 'Create a workflow',
        aiMode: workflowTemplateMode,
        sessionId: null,
        connectionState: 'disconnected',
        isAIAssistantPanelOpen: true,
        aiStore: mockAiStore as AIAssistantStoreInstance,
        workflowData: emptyWorkflowData,
        updateSearchParams: mockUpdateSearchParams,
        clearAIAssistantInitialMessage: mockClearInitialMessage,
      })
    );

    // Should still connect, just without workflow code
    expect(mockAiStore.connect).toHaveBeenCalledWith(
      'workflow_template',
      expect.objectContaining({
        content: 'Create a workflow',
      })
    );
  });
});
