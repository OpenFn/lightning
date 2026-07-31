import type { WorkflowState } from '../../yaml/types';
import { convertWorkflowSpecToState, parseWorkflowYAML } from '../../yaml/util';
import type { Template } from '../types/template';

/**
 * The single definition of what a template's YAML means.
 *
 * Both the read-only preview and the create path go through here, so what the
 * preview draws is by construction what Create builds. Two
 * separate call sites could drift apart in how they parse or normalise, and a
 * preview that lies about the resulting workflow is worse than no preview.
 *
 * Throws on unparseable YAML — user-published templates can contain anything,
 * so every caller has to decide what to do about that.
 */
export function templateToWorkflowState(template: Template): WorkflowState {
  return convertWorkflowSpecToState(parseWorkflowYAML(template.code));
}
