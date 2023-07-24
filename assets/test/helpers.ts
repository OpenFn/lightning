import type { Job } from '../src/types';
import { readFile, writeFile } from 'node:fs/promises';

export async function getFixture<T>(name: string): Promise<T> {
  return JSON.parse(await readFile(`test/fixtures/${name}.json`, 'utf-8'));
}

export async function setFixture<T>(name: string, data: T): Promise<void> {
  await writeFile(`test/fixtures/${name}.json`, JSON.stringify(data, null, 2));
}

export function OnFailJob(upstreamJob: Job, attrs: { name: string }): Job {
  return {
    id: attrs.name.toLowerCase().replace(/[?\W]+/g, '-'),
    adaptor: '@openfn/language-salesforce@2.8.1',
    enabled: true,
    trigger: { type: 'on_job_failure', upstreamJob: upstreamJob.id },
    workflowId: 'workflow-one',
    ...attrs,
  };
}

export function WebhookJob(attrs: { name: string; [key: string]: any }): Job {
  return {
    id: attrs.name.toLowerCase().replace(/[?\W]+/g, '-'),
    adaptor: '@openfn/language-salesforce@2.8.1',
    enabled: true,
    trigger: { type: 'webhook' },
    workflowId: 'workflow-one',
    ...attrs,
  };
}
