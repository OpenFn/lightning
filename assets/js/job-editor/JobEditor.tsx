import pDebounce from 'p-debounce';
import React from 'react';

import type { Lightning } from '#/workflow-diagram/types';

import { EDITOR_DEBOUNCE_MS } from '../common';
import { sortMetadata } from '../metadata-loader/metadata';
import type { WithActionProps } from '../react/lib/with-props';
import { useWorkflowStore } from '../workflow-store/store';

import JobEditorComponent from './JobEditorComponent';

interface JobEditorProps {
  job_id: string;
  adaptor: string;
  source: string;
  disabled: boolean;
  disabled_message: string;
}

export const JobEditor: WithActionProps<JobEditorProps> = props => {
  const [metadata, setMetadata] = React.useState<false | object>(false);
  const [source, setSource] = React.useState('');

  const { change, getById } = useWorkflowStore();

  // debounce editor content update
  const debouncedPushChange = pDebounce((content: string) => {
    change({ jobs: [{ id: props.job_id, body: content }] });
  }, EDITOR_DEBOUNCE_MS);

  // init hook - getting metadata
  React.useEffect(() => {
    const cleanup = props.handleEvent('metadata_ready', payload => {
      // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
      const sortedMetadata = sortMetadata(payload);
      setMetadata(sortedMetadata as object);
    });
    props.pushEventTo('request_metadata', {});
    return cleanup;
  }, [props]);

  React.useEffect(() => {
    const foundJob = getById<Lightning.Job>(props.job_id);
    if (!foundJob) setSource(props.source);
    else setSource(foundJob.body);
  }, [getById, props.job_id, props.source]);

  return (
    <JobEditorComponent
      adaptor={props.adaptor}
      source={source}
      metadata={metadata}
      disabled={props.disabled}
      disabledMessage={props.disabled_message}
      // eslint-disable-next-line @typescript-eslint/no-misused-promises
      onSourceChanged={debouncedPushChange}
    />
  );
};
