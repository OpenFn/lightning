// Thin pass-through. New code should import from `./format`, `./v1`, or
// `./v2` directly. See plan #4718.
//
// Phase 4 cutover: outbound YAML is v2-only. The v1 state→spec serializer
// (`convertWorkflowStateToSpec`) and the v1 `serializeWorkflow` helper have
// been removed; v1 lives on as a parser only. Callers that previously did
// `convertWorkflowStateToSpec(state, false) → YAML.stringify` should call
// `serializeWorkflow(state)` from `./format`.
//
// Phase 5 cutover: inbound YAML auto-detects v1 vs v2 and dispatches to the
// matching parser. The exported `parseWorkflowYAML` and
// `parseWorkflowTemplate` here are the format-aware façades — feature
// components should call these rather than reaching into `./v1` or `./v2`
// directly.

import YAML from 'yaml';

import { parseWorkflow as parseWorkflowFormatAware } from './format';
import type { WorkflowSpec } from './types';
import * as v2 from './v2';
import {
  WorkflowError,
  YamlSyntaxError,
  createWorkflowError,
} from './workflow-errors';

export {
  applyJobCredsToWorkflowState,
  convertWorkflowSpecToState,
  extractJobCredentials,
} from './v1';

export { serializeWorkflow } from './format';

/**
 * Parse a workflow YAML string. Detects v1 vs v2 format and dispatches to
 * the matching parser. Returns a v1-shaped `WorkflowSpec` regardless of the
 * input format, so downstream callers (e.g. `convertWorkflowSpecToState`)
 * stay format-agnostic.
 */
export const parseWorkflowYAML = (yamlString: string): WorkflowSpec => {
  try {
    return parseWorkflowFormatAware(yamlString).spec;
  } catch (error) {
    // Re-throw structured workflow errors as-is; they carry actionable
    // context for the UI.
    if (error instanceof WorkflowError) {
      throw error;
    }

    // YAML parse errors get wrapped with a friendly class.
    if (error instanceof Error && error.name === 'YAMLParseError') {
      throw new YamlSyntaxError(error.message, error);
    }

    throw createWorkflowError(error);
  }
};

/**
 * Parse a `WorkflowTemplate.code` string. Templates published from the
 * canvas (Phase 4 onward) are v2; legacy `WorkflowTemplate` rows in the DB
 * remain v1. Format detection happens here at read time so the template
 * picker keeps working for both shapes — no DB migration needed.
 */
export const parseWorkflowTemplate = (code: string): WorkflowSpec => {
  let parsed: unknown;
  try {
    parsed = YAML.parse(code);
  } catch (error) {
    if (error instanceof Error && error.name === 'YAMLParseError') {
      throw new YamlSyntaxError(error.message, error);
    }
    throw createWorkflowError(error);
  }

  // Empty / non-object docs flow through unchanged so the template picker's
  // historic "no schema validation" behavior is preserved for hand-edited
  // legacy templates.
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return parsed as WorkflowSpec;
  }

  const format = v2.detectFormat(parsed);
  if (format === 'v2') {
    return v2.parseWorkflow(parsed);
  }

  // v1 templates retain the legacy "lenient" parse path: just hand back the
  // parsed map so a partially-shaped template doesn't fail the picker. This
  // matches behavior prior to Phase 5.
  return parsed as WorkflowSpec;
};
