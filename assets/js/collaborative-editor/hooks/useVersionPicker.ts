import { useExperimentalFeatures, useProject } from './useSessionContext';
import { useSessionWorkflow } from './useSessionContext';

/**
 * Which version list the editor is showing.
 *
 * `releases` is the publish trail: what went to production, when, by whom, with
 * Restore on each. It only means something where a workflow can publish, which
 * is a live workflow outside a sandbox.
 *
 * `snapshots` is every save, which is the list the editor has always had. A
 * draft has published nothing, and nothing in a sandbox reaches production, so
 * both browse their saves rather than a trail of publishes that would be either
 * empty or misleading.
 *
 * One hook rather than the condition written twice, because the answer decides
 * two things that have to agree: which component renders, and which URL
 * parameter pins a version. A release number and a snapshot's lock_version are
 * different numbers for different content, so disagreeing would open the wrong
 * document.
 */
export type VersionPicker = 'releases' | 'snapshots';

export function useVersionPicker(): VersionPicker {
  const experimentalFeatures = useExperimentalFeatures();
  const project = useProject();
  const workflow = useSessionWorkflow();

  if (!experimentalFeatures) return 'snapshots';
  if (project?.is_sandbox === true) return 'snapshots';

  return workflow?.state === 'live' ? 'releases' : 'snapshots';
}
