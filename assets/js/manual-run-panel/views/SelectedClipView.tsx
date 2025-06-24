import { DataclipViewer } from "../../react/components/DataclipViewer"
import { DocumentTextIcon, ClockIcon } from "@heroicons/react/24/outline"
import Pill from "../Pill"
import truncateUid from "../../utils/truncateUID";
import formatDate from "../../utils/formatDate";
import DataclipTypePill from "../DataclipTypePill";
import type { Dataclip } from "../types";

const iconStyle = 'h-4 w-4 text-grey-400';

interface SelectedClipViewProps {
  dataclip: Dataclip
  onUnselect: () => void
  isNextCronRun?: boolean
}

const SelectedClipView: React.FC<SelectedClipViewProps> = ({ dataclip, onUnselect, isNextCronRun = false }) => {
  return <>
    <div className="flex flex-col flex-0 gap-2">
      {isNextCronRun && (
        <div className="flex items-center gap-2 px-3 py-2 bg-orange-50 border border-orange-200 rounded-md">
          <ClockIcon className="h-4 w-4 text-orange-500" />
          <span className="text-sm text-orange-800 font-medium">
            Next Input for Cron
          </span>
          <span className="text-xs text-orange-600">
            This was the output of the last successful run and will be used for the next run. Create a custom input or select "empty" to clear state for this cron-triggered workflow.
          </span>
        </div>
      )}
      <Pill onClose={onUnselect}>
        <div className='flex py-1 grow items-center justify-between'>
          <div className="flex gap-1 items-center text-sm">
            {' '}
            {isNextCronRun ? (
              <ClockIcon
                className="h-4 w-4 text-orange-400"
              />
            ) : (
              <DocumentTextIcon
                className={`${iconStyle} group-hover:scale-110 group-hover:text-primary-600`}
              />
            )}
            {' '}
            {truncateUid(dataclip.id)}{' '}
          </div>
          <div className="text-xs truncate ml-2">
            {formatDate(new Date(dataclip.updated_at))}
          </div>
        </div>
      </Pill>
      <div className="flex flex-row min-h-[28px] items-center mx-1">
        <div className="basis-1/2 font-medium text-secondary-700 text-sm">
          Type
        </div>
        <div className="basis-1/2 text-right">
          <DataclipTypePill type={dataclip.type} />
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
    <DataclipViewer dataclipId={dataclip.id} />
  </>
}

export default SelectedClipView;