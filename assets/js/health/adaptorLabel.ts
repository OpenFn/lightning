import {
  extractPackageName,
  getAdaptorDisplayName,
} from '#/collaborative-editor/utils/adaptorUtils';

// The name the workflow diagram shows under a job, plus "adaptor": "gmail
// adaptor". The version is left off because rows are grouped by `job_id`, so
// one row can span an adaptor upgrade. An adaptor the helper can't name shows
// as its package name.
export const adaptorLabel = (adaptor: string) =>
  `${getAdaptorDisplayName(adaptor, { fallback: extractPackageName(adaptor) })} adaptor`;
