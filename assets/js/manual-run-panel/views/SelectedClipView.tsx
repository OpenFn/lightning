import { DataclipViewer } from '../../react/components/DataclipViewer';
import { DocumentTextIcon } from '@heroicons/react/24/outline';
import { ClockIcon } from '@heroicons/react/24/solid';
import Pill from '../Pill';
import truncateUid from '../../utils/truncateUID';
import formatDate from '../../utils/formatDate';
import DataclipTypePill from '../DataclipTypePill';
import type { Dataclip } from '../types';

const iconStyle = 'h-4 w-4 text-grey-400';

interface SelectedClipViewProps {
  dataclip: Dataclip;
  onUnselect: () => void;
  isNextCronRun?: boolean;
}

const SelectedClipView: React.FC<SelectedClipViewProps> = ({ dataclip, onUnselect, isNextCronRun = false, }) => {
  return <div className="relative h-full flex flex-col overflow-hidden">
    <div className="flex flex-col flex-0 gap-2">
      {isNextCronRun && (
        <div className="alert-warning flex flex-col gap-1 px-3 py-2 rounded-md border">
          <span className="text-sm font-medium">
            Default Next Input for Cron
          </span>
          <span className="text-xs">
            This workflow has a "cron" trigger, and by default it will use the
            input below for its next run. You can override that by starting a
            manual run with an empty input or a custom input at any time.
          </span>
        </div>
      )}
      <Pill onClose={onUnselect}>
        <div className="flex py-1 grow items-center justify-between">
          <div className="flex gap-1 items-center text-sm">
            {' '}
            {isNextCronRun ? (
              <ClockIcon
                className={`${iconStyle} group-hover:scale-110 group-hover:text-primary-600`}
              />
            ) : (
            <DocumentTextIcon
              className={`${iconStyle} group-hover:scale-110 group-hover:text-primary-600`}
            />{' '}
            {truncateUid(dataclip.id)}{' '}
          </div>
          <div className="text-xs truncate ml-2">
            {formatDate(new Date(dataclip.inserted_at))}
          </div>
        </div>
        <div className="flex flex-row min-h-[28px] items-center mx-1">
          <div className="basis-1/2 font-medium text-secondary-700 text-sm">
            Created at
          </div>
          <div className="basis-1/2 text-right text-sm text-nowrap">
            {formatDate(new Date(dataclip.inserted_at))}
          </div>
        </div>
        <div className="flex flex-row min-h-[28px] items-center mx-1">
          <div className="basis-1/2 font-medium text-secondary-700 text-sm">
            UUID
          </div>
          <div className="basis-1/2 text-right text-sm text-nowrap">
            {dataclip.id}
          </div>
        </div>
      </div>
    </div>
    <DataclipViewer dataclipId={dataclip.id} />
  </div>
}

export default SelectedClipView;
