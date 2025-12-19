/**
 * URL Conversion Utilities for Classical ↔ Collaborative Editor
 *
 * This module provides bidirectional query parameter conversion between
 * the classical editor and the collaborative editor. The mappings are
 * centralized here to ensure consistency across the application.
 *
 * @module editorUrlConversion
 */

/**
 * Mapping configuration for query parameter conversion
 */
const PARAM_MAPPINGS = {
  // Classical -> Collaborative
  classicalToCollaborative: {
    a: 'run', // Followed run ID
    s: ['job', 'trigger', 'edge'], // Selected step (type determined by context)
    m: {
      // Mode/Panel mappings
      expand: 'editor',
      workflow_input: 'run',
      settings: 'settings',
    },
  },

  // Collaborative -> Classical
  collaborativeToClassical: {
    run: 'a', // Followed run ID
    selection: 's', // Job/trigger/edge all map to 's'
    panel: {
      // Panel/Mode mappings
      editor: 'expand',
      run: 'workflow_input',
      settings: 'settings',
    },
  },

  // Params that should be preserved as-is in both directions
  preservedParams: ['v', 'method', 'w-chat', 'j-chat', 'code'],

  // Params that are editor-specific and should be skipped
  classicalOnlyParams: ['m'], // Handled specially, converted to panel
  collaborativeOnlyParams: ['panel', 'job', 'trigger', 'edge'], // Handled specially
} as const;

/**
 * Converts collaborative editor query params to classical editor params
 *
 * @param searchParams - URLSearchParams from collaborative editor
 * @returns URLSearchParams formatted for classical editor
 *
 * @example
 * const collab = new URLSearchParams('run=123&job=abc&panel=editor');
 * const classical = collaborativeToClassicalParams(collab);
 * // Returns: ?a=123&s=abc&m=expand
 */
export function collaborativeToClassicalParams(
  searchParams: URLSearchParams
): URLSearchParams {
  const classicalParams = new URLSearchParams();

  for (const [key, value] of searchParams.entries()) {
    if (key === 'run') {
      // Convert run -> a (followed run)
      classicalParams.set('a', value);
    } else if (key === 'job' || key === 'trigger' || key === 'edge') {
      // Convert job/trigger/edge -> s (selected step)
      // All three types collapse into single 's' param in classical editor
      classicalParams.set('s', value);
    } else if (key === 'panel') {
      // Convert panel values to mode values
      const panelToMode = PARAM_MAPPINGS.collaborativeToClassical
        .panel as Record<string, string>;
      const mode = panelToMode[value];
      if (mode) {
        classicalParams.set('m', mode);
      }
      // panel param itself is not preserved - only converted to m
    } else if (PARAM_MAPPINGS.preservedParams.includes(key)) {
      // Preserve params that are the same in both editors
      classicalParams.set(key, value);
    } else {
      // Future-proof: preserve unknown params
      classicalParams.set(key, value);
    }
  }

  return classicalParams;
}

/**
 * Converts classical editor query params to collaborative editor params
 *
 * Note: This is primarily used server-side (Elixir), but included here for
 * completeness and potential client-side use cases.
 *
 * @param searchParams - URLSearchParams from classical editor
 * @param context - Optional context to determine selection type for 's' param
 * @returns URLSearchParams formatted for collaborative editor
 *
 * @example
 * const classical = new URLSearchParams('a=123&s=abc&m=expand');
 * const collab = classicalToCollaborativeParams(classical, { selectedType: 'job' });
 * // Returns: ?run=123&job=abc&panel=editor
 */
export function classicalToCollaborativeParams(
  searchParams: URLSearchParams,
  context?: {
    selectedType?: 'job' | 'trigger' | 'edge';
  }
): URLSearchParams {
  const collaborativeParams = new URLSearchParams();

  for (const [key, value] of searchParams.entries()) {
    if (!value) continue; // Skip nil/empty values

    if (key === 'a') {
      // Convert a -> run (followed run)
      collaborativeParams.set('run', value);
    } else if (key === 's') {
      // Convert s -> job/trigger/edge (based on context)
      // Default to 'job' if context not provided (backwards compatibility)
      const selectedType = context?.selectedType ?? 'job';
      collaborativeParams.set(selectedType, value);
    } else if (key === 'm') {
      // Convert mode values to panel values
      const modeToPanel = PARAM_MAPPINGS.classicalToCollaborative.m as Record<
        string,
        string
      >;
      const panel = modeToPanel[value];
      if (panel) {
        collaborativeParams.set('panel', panel);
      }
      // m param itself is not preserved - only converted to panel
    } else if (key === 'panel') {
      // Skip panel param from classical side (shouldn't exist there)
      continue;
    } else if (PARAM_MAPPINGS.preservedParams.includes(key)) {
      // Preserve params that are the same in both editors
      collaborativeParams.set(key, value);
    } else {
      // Future-proof: preserve unknown params
      collaborativeParams.set(key, value);
    }
  }

  return collaborativeParams;
}

/**
 * Builds a complete classical editor URL from collaborative editor context
 *
 * @param options - URL building options
 * @returns Complete URL string for classical editor
 *
 * @example
 * const url = buildClassicalEditorUrl({
 *   projectId: 'proj-123',
 *   workflowId: 'wf-456',
 *   searchParams: new URLSearchParams('run=789&job=abc&panel=editor'),
 *   isNewWorkflow: false
 * });
 * // Returns: /projects/proj-123/w/wf-456?a=789&s=abc&m=expand
 */
export function buildClassicalEditorUrl(options: {
  projectId: string;
  workflowId: string | null;
  searchParams: URLSearchParams;
  isNewWorkflow?: boolean;
}): string {
  const {
    projectId,
    workflowId,
    searchParams,
    isNewWorkflow = false,
  } = options;

  const classicalParams = collaborativeToClassicalParams(searchParams);
  const queryString =
    classicalParams.toString().length > 0
      ? `?${classicalParams.toString()}`
      : '';

  const basePath = isNewWorkflow
    ? `/projects/${projectId}/w/new`
    : `/projects/${projectId}/w/${workflowId}`;

  return `${basePath}${queryString}`;
}

/**
 * Builds a complete collaborative editor URL from classical editor context
 *
 * @param options - URL building options
 * @returns Complete URL string for collaborative editor
 *
 * @example
 * const url = buildCollaborativeEditorUrl({
 *   projectId: 'proj-123',
 *   workflowId: 'wf-456',
 *   searchParams: new URLSearchParams('a=789&s=abc&m=expand'),
 *   isNewWorkflow: false,
 *   selectedType: 'job'
 * });
 * // Returns: /projects/proj-123/w/wf-456/collaborate?run=789&job=abc&panel=editor
 */
export function buildCollaborativeEditorUrl(options: {
  projectId: string;
  workflowId: string | null;
  searchParams: URLSearchParams;
  isNewWorkflow?: boolean;
  selectedType?: 'job' | 'trigger' | 'edge';
}): string {
  const {
    projectId,
    workflowId,
    searchParams,
    isNewWorkflow = false,
    selectedType,
  } = options;

  const collaborativeParams = classicalToCollaborativeParams(searchParams, {
    selectedType,
  });
  const queryString =
    collaborativeParams.toString().length > 0
      ? `?${collaborativeParams.toString()}`
      : '';

  const basePath = isNewWorkflow
    ? `/projects/${projectId}/w/new/collaborate?method=template`
    : `/projects/${projectId}/w/${workflowId}/collaborate`;

  return `${basePath}${queryString}`;
}

/**
 * Type guard to check if a value is a valid panel type
 */
export function isValidPanelType(
  value: string
): value is 'editor' | 'run' | 'settings' {
  return ['editor', 'run', 'settings'].includes(value);
}

/**
 * Type guard to check if a value is a valid mode type
 */
export function isValidModeType(
  value: string
): value is 'expand' | 'workflow_input' | 'settings' {
  return ['expand', 'workflow_input', 'settings'].includes(value);
}

/**
 * Gets the mapping configuration (useful for testing and validation)
 */
export function getMappingConfig() {
  return PARAM_MAPPINGS;
}
