// Format façade — single boundary between Lightning's runtime workflow state
// and YAML files. Knows about format versions; delegates to `./v1` or `./v2`.
//
// Phase 4 wiring: outbound serialization emits v2 (CLI-aligned portability
// format) only — there is no v1 export path remaining in the codebase.
// Inbound parsing dispatches by detected format and continues to accept both
// v1 and v2 documents (Phase 5). See plan #4718.

import YAML from 'yaml';

import type { WorkflowSpec, WorkflowState } from './types';
import * as v1 from './v1';
import * as v2 from './v2';

export type FormatVersion = 'v1' | 'v2';
export type ParsedDoc = { format: FormatVersion; spec: WorkflowSpec };

// Outbound: v2 only. v1 export was removed in Phase 4 of #4718.
export const serializeWorkflow = (state: WorkflowState): string => {
  return v2.serializeWorkflow(state);
};

// Inbound: detects format and dispatches.
export const parseWorkflow = (yamlString: string): ParsedDoc => {
  const parsed = YAML.parse(yamlString);
  const format = detectFormat(parsed);
  if (format === 'v2') {
    return { format, spec: v2.parseWorkflow(parsed) };
  }
  return { format, spec: v1.parseWorkflow(parsed) };
};

export const detectFormat = (parsed: unknown): FormatVersion => {
  return v2.detectFormat(parsed);
};
