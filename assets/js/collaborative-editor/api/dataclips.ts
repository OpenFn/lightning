import type { Dataclip } from '../../manual-run-panel/types';
import { getCsrfToken } from '../lib/csrf';

export type { Dataclip };

export interface DataclipFilters {
  type?: string;
  before?: string;
  after?: string;
  named_only?: boolean;
}

export interface SearchDataclipsResponse {
  data: Dataclip[];
  next_cron_run_dataclip_id: string | null;
  can_edit_dataclip: boolean;
}

export interface ManualRunParams {
  workflowId: string;
  projectId: string;
  jobId?: string;
  triggerId?: string;
  dataclipId?: string;
  customBody?: string;
}

export interface ManualRunResponse {
  data: {
    workorder_id: string;
    run_id: string;
    dataclip?: Dataclip;
  };
}

/**
 * Search dataclips for a job with filters
 */
export async function searchDataclips(
  projectId: string,
  jobId: string,
  query?: string,
  filters?: DataclipFilters
): Promise<SearchDataclipsResponse> {
  const params = new URLSearchParams({
    ...(query && { query }),
    ...(filters?.type && { type: filters.type }),
    ...(filters?.before && { before: filters.before }),
    ...(filters?.after && { after: filters.after }),
    ...(filters?.named_only !== undefined && {
      named_only: String(filters.named_only),
    }),
    limit: '10',
  });

  const response = await fetch(
    `/projects/${projectId}/jobs/${jobId}/dataclips?${params}`,
    {
      credentials: 'same-origin',
    }
  );

  if (!response.ok) {
    throw new Error(`Failed to search dataclips: ${response.statusText}`);
  }

  return response.json() as Promise<SearchDataclipsResponse>;
}

/**
 * Get dataclip for a specific run
 */
export async function getRunDataclip(
  projectId: string,
  runId: string,
  jobId: string
): Promise<{ dataclip: Dataclip | null; run_step: any | null }> {
  const response = await fetch(
    `/projects/${projectId}/runs/${runId}/dataclip?job_id=${jobId}`,
    {
      credentials: 'same-origin',
    }
  );

  if (!response.ok) {
    throw new Error(`Failed to get run dataclip: ${response.statusText}`);
  }

  return response.json() as Promise<{
    dataclip: Dataclip | null;
    run_step: any | null;
  }>;
}

/**
 * Update dataclip name
 */
export async function updateDataclipName(
  projectId: string,
  dataclipId: string,
  name: string | null
): Promise<{ data: Dataclip }> {
  const csrfToken = getCsrfToken();

  const response = await fetch(
    `/projects/${projectId}/dataclips/${dataclipId}`,
    {
      method: 'PATCH',
      credentials: 'same-origin',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken || '',
      },
      body: JSON.stringify({ name }),
    }
  );

  if (!response.ok) {
    let errorMessage = 'Failed to update dataclip name';
    try {
      const error = (await response.json()) as { error?: string };
      errorMessage = error.error || errorMessage;
    } catch {
      errorMessage = `${errorMessage} (${response.status})`;
    }
    throw new Error(errorMessage);
  }

  return response.json() as Promise<{ data: Dataclip }>;
}

/**
 * Submit manual run
 */
export async function submitManualRun(
  params: ManualRunParams
): Promise<ManualRunResponse> {
  const csrfToken = getCsrfToken();

  const body: any = {};
  if (params.jobId) body.job_id = params.jobId;
  if (params.triggerId) body.trigger_id = params.triggerId;
  if (params.dataclipId) body.dataclip_id = params.dataclipId;
  if (params.customBody) body.custom_body = params.customBody;

  const response = await fetch(
    `/projects/${params.projectId}/workflows/${params.workflowId}/runs`,
    {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken || '',
      },
      body: JSON.stringify(body),
    }
  );

  if (!response.ok) {
    const error = (await response.json()) as { error?: string };
    throw new Error(error.error || 'Failed to submit manual run');
  }

  return response.json() as Promise<ManualRunResponse>;
}
