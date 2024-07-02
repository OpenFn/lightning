import React from 'react';
import { createRoot } from 'react-dom/client';
import type JobEditor from './JobEditor';
import { sortMetadata } from '../metadata-loader/metadata';
import { LiveSocket, PhoenixHook } from '../hooks/PhoenixHook';
import type WorkflowEditorEntrypoint from '../workflow-editor';
import pRetry from 'p-retry';
import pDebounce from 'p-debounce';
import { WorkflowStore } from '../workflow-editor/store';
import { Lightning } from '../workflow-diagram/types';

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

const EDITOR_DEBOUNCE_MS = 300;

export default {
  findWorkflowEditorStore() {
    return pRetry(
      () => {
        console.debug('Looking up WorkflowEditorHook');
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
  mounted(this: JobEditorEntrypoint) {
    window.jobEditor = this;

    console.group('JobEditor');
    console.debug('Mounted');
    this._debouncedPushChange = pDebounce(this.pushChange, EDITOR_DEBOUNCE_MS);

    import('./JobEditor').then(module => {
      console.group('JobEditor');
      console.debug('loaded module');
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
      this.requestMetadata().then(() => this.render());
      console.groupEnd();
    });

    console.groupEnd();
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

    this.findWorkflowEditorStore().then(workflowStore => {
      const job = workflowStore.getState().getById<Lightning.Job>(jobId);

      if (!job) {
        console.error('Job not found', jobId);
        return;
      }

      if (JobEditorComponent) {
        this.componentRoot?.render(
          <JobEditorComponent
            adaptor={adaptor}
            source={job.body}
            metadata={this.metadata}
            disabled={disabled === 'true'}
            disabledMessage={disabledMessage}
            onSourceChanged={src => this.handleContentChange(src)}
          />
        );
      }
    });
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
  if (adaptor.split('@').at(-1) === 'latest') {
    console.warn(
      "job-editor hook received an adaptor with @latest as it's version - to load docs a specific version must be provided"
    );
  }
}
