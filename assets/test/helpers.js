import { readFile, writeFile } from 'node:fs/promises';
export async function getFixture(name) {
    return JSON.parse(await readFile(`test/fixtures/${name}.json`, 'utf-8'));
}
export async function setFixture(name, data) {
    await writeFile(`test/fixtures/${name}.json`, JSON.stringify(data, null, 2));
}
export function OnFailJob(upstreamJob, attrs) {
    return {
        id: attrs.name.toLowerCase().replace(/[?\W]+/g, '-'),
        adaptor: '@openfn/language-salesforce@2.8.1',
        enabled: true,
        trigger: { type: 'on_job_failure', upstreamJob: upstreamJob.id },
        workflowId: 'workflow-one',
        ...attrs,
    };
}
export function WebhookJob(attrs) {
    return {
        id: attrs.name.toLowerCase().replace(/[?\W]+/g, '-'),
        adaptor: '@openfn/language-salesforce@2.8.1',
        enabled: true,
        trigger: { type: 'webhook' },
        workflowId: 'workflow-one',
        ...attrs,
    };
}
