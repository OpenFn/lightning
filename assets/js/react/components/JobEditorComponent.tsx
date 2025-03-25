import React from "react"
import JobEditor from "../../job-editor/JobEditor"
import type { WithActionProps } from "../lib/with-props";
import { sortMetadata } from "../../metadata-loader/metadata";

interface JobEditorComponentProps {
  adaptor: string,
  source: string,
  disabled: boolean,
  disabled_message: string,
}

export const JobEditorComponent: WithActionProps<JobEditorComponentProps> = (props) => {
  const [metadata, setMetadata] = React.useState<false | object>(false);

  React.useEffect(() => {
    // request metadata right here in react
    props.handleEvent('metadata_ready', (payload) => {
      setMetadata(payload as object);
      // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
      const sortedMetadata = sortMetadata(payload);
      setMetadata(sortedMetadata as object);
    })
    props.pushEventTo('request_metadata', {});
  }, [props])

  return <JobEditor
    adaptor={props.adaptor}
    source={props.source}
    metadata={metadata}
    disabled={props.disabled}
    disabledMessage={props.disabled_message}
    onSourceChanged={(src_1: string) => { console.log("src_1:", src_1) }}
  />
}