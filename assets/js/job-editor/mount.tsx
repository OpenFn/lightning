import pDebounce from 'p-debounce';
import pRetry from 'p-retry';
import { createRoot } from 'react-dom/client';
import { EDITOR_DEBOUNCE_MS } from '../common';
import type { LiveSocket } from 'phoenix_live_view';
import type {
  PhoenixHook,
  GetPhoenixHookInternalThis,
} from '../hooks/PhoenixHook';
import { sortMetadata } from '../metadata-loader/metadata';
import type { Lightning } from '../workflow-diagram/types';
import type WorkflowEditorEntrypoint from '../workflow-editor';
import type { WorkflowStore } from '../workflow-editor/store';
import type JobEditor from './JobEditor';

declare global {
  interface Window {
    jobEditor?: GetPhoenixHookInternalThis<JobEditorEntrypoint> | undefined;
  }
}

type JobEditorEntrypoint = PhoenixHook<
  {
    componentRoot: ReturnType<typeof createRoot> | null;
    changeEvent: string;
    field?: HTMLTextAreaElement | null;
    findWorkflowEditorStore(): Promise<WorkflowStore>;
    workflowEditorStore: WorkflowStore;
    handleContentChange(content: string): Promise<void>;
    metadata?: true | object;
    observer: MutationObserver | null;
    render(): void;
    requestMetadata(): Promise<{}>;
    setupObserver(): void;
    pushChange(content: string): Promise<void>;
    _debouncedPushChange(content: string): Promise<void>;
    currentContent: string;
  },
  {
    adaptor: string;
    source: string;
    disabled: string;
    disabledMessage: string;
    jobID: string;
  }
>;

type AttributeMutationRecord = MutationRecord & {
  attributeName: string;
  oldValue: string;
};

let JobEditorComponent: typeof JobEditor | undefined;

export default {
  findWorkflowEditorStore(): Promise<WorkflowStore> {
    return pRetry(
      attempt => {
        console.debug('Looking up WorkflowEditorHook', { attempt });
        return lookupWorkflowEditorHook(this.liveSocket, this.el);
      },
      { retries: 5 }
    ).then(hook => {
      return hook.workflowStore;
    });
  },
  reconnected() {
    console.debug('Reconnected JobEditor');
    // this.handleContentChange(this.currentContent);
  },
  mounted() {
    let event = 'editor load';
    let start = instrumentStart(event);

    window.jobEditor = this;

    this._debouncedPushChange = pDebounce(this.pushChange, EDITOR_DEBOUNCE_MS);

    import('./JobEditor').then(module => {
      JobEditorComponent = module.default as typeof JobEditor;
      this.componentRoot = createRoot(this.el);

      const { changeEvent } = this.el.dataset;
      if (changeEvent) {
        this.changeEvent = changeEvent;
      } else {
        console.warn('Warning: No changeEvent set. Content will not sync.');
      }
      this.setupObserver();
      this.render();

      let end = instrumentEnd(event);

      this.pushEventTo(this.el, 'job_editor_metrics_report', {
        metrics: [{ event, start, end }],
      });

      this.requestMetadata().then(() => this.render());
    });
  },
  handleContentChange(content: string) {
    this._debouncedPushChange(content);
  },
  async pushChange(content: string) {
    console.debug('pushChange', content);
    const jobId = this.el.dataset.jobId;

    if (!jobId) {
      throw new Error(
        'No jobId found on JobEditor element, refusing to push change'
      );
    }

    await this.findWorkflowEditorStore().then(workflowStore => {
      workflowStore.getState().change({ jobs: [{ id: jobId, body: content }] });
    });
  },
  render() {
    const { adaptor, disabled, disabledMessage, jobId } = this.el.dataset;

    checkAdaptorVersion(adaptor);

    pRetry(
      async attempt => {
        console.debug('JobEditor', { attempt });

        const workflowStore = await this.findWorkflowEditorStore();
        const job = workflowStore.getState().getById<Lightning.Job>(jobId);
        if (!job) {
          throw new Error('Job not found in store yet');
        }
        if (JobEditorComponent) {
          this.componentRoot?.render(
            <JobEditorComponent
              adaptor={adaptor}
              source={job.body}
              metadata={this.metadata}
              disabled={disabled === 'true'}
              disabledMessage={disabledMessage}
              onSourceChanged={src_1 => this.handleContentChange(src_1)}
            />
          );
        } else {
          throw new Error('JobEditorComponent not loaded yet');
        }
      },
      { retries: 5 }
    );
  },
  requestMetadata() {
    this.metadata = true; // indicate we're loading
    this.render();
    return new Promise(resolve => {
      const callbackRef = this.handleEvent('metadata_ready', data => {
        this.removeHandleEvent(callbackRef);
        const sortedMetadata = sortMetadata(data);
        this.metadata = sortedMetadata;
        resolve(sortedMetadata);
      });

      this.pushEventTo(this.el, 'request_metadata', {});
    });
  },
  setupObserver() {
    this.observer = new MutationObserver(mutations => {
      mutations.forEach(mutation => {
        const { attributeName, oldValue } = mutation as AttributeMutationRecord;
        const newValue = this.el.getAttribute(attributeName);
        if (oldValue !== newValue) {
          this.render();
        }
      });
    });

    this.observer.observe(this.el, {
      attributeFilter: [
        'data-adaptor',
        'data-change-event',
        'data-disabled',
        'data-disabled-message',
      ],
      attributeOldValue: true,
    });
  },
  destroyed() {
    this.componentRoot?.unmount();
    this.observer?.disconnect();
  },
} as JobEditorEntrypoint;

function lookupWorkflowEditorHook(liveSocket: LiveSocket, el: HTMLElement) {
  let found: typeof WorkflowEditorEntrypoint | undefined;
  liveSocket.withinOwners(el, view => {
    for (let hook of Object.values(view.viewHooks)) {
      if (hook.el.getAttribute('phx-hook') === 'WorkflowEditor') {
        found = hook as typeof WorkflowEditorEntrypoint;
        break;
      }
    }
  });

  if (!found) {
    throw new Error('WorkflowEditor hook not found');
  }

  return found;
}

function checkAdaptorVersion(adaptor: string) {
  let slugs = adaptor.split('@');
  if (slugs[slugs.length - 1] === 'latest') {
    console.warn(
      "job-editor hook received an adaptor with @latest as it's version - to load docs a specific version must be provided"
    );
  }
}

function instrumentStart(label: string) {
  let time = new Date();
  console.debug(`${label} - start`, time.toISOString());
  console.time(label);
  return time.getTime();
}

function instrumentEnd(label: string) {
  let time = new Date();
  console.debug(`${label} - end`, time.toISOString());
  console.timeEnd(label);
  return time.getTime();
}
