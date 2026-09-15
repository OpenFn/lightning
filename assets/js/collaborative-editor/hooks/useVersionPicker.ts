/**
 * Which version list the editor shows. `releases` is the publish trail, which
 * only means something on a live workflow outside a sandbox; everything else
 * browses its saves. The answer picks both the component and the URL parameter,
 * and those two have to agree.
 */

import {
  useExperimentalFeatures,
  useProject,
  useSessionWorkflow,
} from './useSessionContext';

export type VersionPicker = 'releases' | 'snapshots';

export function useVersionPicker(): VersionPicker {
  const experimentalFeatures = useExperimentalFeatures();
  const project = useProject();
  const workflow = useSessionWorkflow();

  if (!experimentalFeatures) return 'snapshots';
  if (project?.is_sandbox === true) return 'snapshots';

  return workflow?.state === 'live' ? 'releases' : 'snapshots';
}
