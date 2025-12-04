import type { Channel } from 'phoenix';

import { channelRequest } from '../hooks/useChannel';

import type { WorkflowTemplate } from '../types/template';

export async function fetchTemplates(
  channel: Channel
): Promise<WorkflowTemplate[]> {
  const response = await channelRequest<{ templates: WorkflowTemplate[] }>(
    channel,
    'list_templates',
    {}
  );
  return response.templates;
}
