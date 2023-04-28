import React, { useState } from 'react';
import { ClockIcon, KeyIcon } from '@heroicons/react/24/outline';
import { InformationCircleIcon } from '@heroicons/react/24/solid';
import Entity from './Entity';
import Empty from './Empty';
import mapChildren from './map-children';

const PERSIST_KEY = 'lightning.metadata-explorer.settings';

const iconStyle = 'h-4 w-4 text-grey-400 mr-1';

type MetadataExplorerProps = {
  metadata?: true | null | any;
  adaptor: string;
  credentialName?: string;
};

export default ({
  metadata,
  adaptor,
  credentialName,
}: MetadataExplorerProps) => {
  if (!metadata) {
    return <Empty adaptor={adaptor} />;
  }
  if (metadata === true) {
    return <div className="block m-2">Loading metadata...</div>;
  }
  if (metadata.error) {
    const { error } = metadata;
    if (error === 'no_metadata_function') return <Empty adaptor={adaptor} />;

    let message = `An error occurred while loading metadata: ${error}`;

    if (error === 'no_credential')
      message =
        "Metadata can only be loaded once you've added a valid credential.";

    if (error === 'no_metadata_result')
      message = `The ${adaptor} adaptor isn't returning any metadata. This could be because your credential is invalid or not authorized to access the metadata APIs for your system.`;

    return <div className="block m-2">{message}</div>;
  }

  const [initialShowHelp] = useState(() => {
    const settings = localStorage.getItem(PERSIST_KEY);
    if (settings) {
      return JSON.parse(settings).showHelp;
    }
    return true;
  });

  const handleToggleHelp = (evt: any) => {
    const settings = { showHelp: evt.target.open };
    localStorage.setItem(PERSIST_KEY, JSON.stringify(settings));
  };

  const dateString = new Date(metadata.created).toLocaleString();

  return (
    <div className="block flex-1 flex flex-col overflow-y-hidden">
      <div className="mt-2 flex-1 overflow-y-auto">
        {mapChildren(metadata, data => (
          <Entity level={0} data={data} key={data.name} />
        ))}
      </div>
      <div className="pt-4">
        <div className="flex flex-row flex-wrap">
          <p
            className="flex flex-row cursor-default mr-2 whitespace-nowrap"
            title={`This metadata was generated at ${dateString}`}
          >
            <ClockIcon className={iconStyle} />
            <span className="text-xs mb-1">{dateString}</span>
          </p>
          {credentialName && (
            <p
              className="flex flex-row cursor-default mr-2 whitespace-nowrap"
              title="The credential used to generate metadata"
            >
              <KeyIcon className={iconStyle} />
              <span className="text-xs mb-1">{credentialName}</span>
            </p>
          )}
        </div>
        <details open={initialShowHelp} onToggle={handleToggleHelp}>
          <summary className="block cursor-pointer text-sm">
            <InformationCircleIcon className={iconStyle + ' inline'} />
            <span className="font-bold">Tips</span>
          </summary>
          <div
            className="border-slate-200 border-l-2 ml-2 pl-2"
            style={{ borderLeftWidth: '2px' }}
          >
            <p className="text-sm mb-2">
              Metadata shows you the structure of your datasource, based on your
              current credential.
            </p>
            <p className="text-sm mb-2">
              Press <code className="inline text-xs">ctrl + space</code> in the
              code editor for suggestions while writing code.
            </p>
          </div>
        </details>
      </div>
    </div>
  );
};
