import type { Job } from '../src/types';
export declare function getFixture<T>(name: string): Promise<T>;
export declare function setFixture<T>(name: string, data: T): Promise<void>;
export declare function OnFailJob(upstreamJob: Job, attrs: {
    name: string;
}): Job;
export declare function WebhookJob(attrs: {
    name: string;
    [key: string]: any;
}): Job;
