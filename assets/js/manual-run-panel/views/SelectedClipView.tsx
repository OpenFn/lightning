import { DataclipViewer } from "../../react/components/DataclipViewer"
import { DocumentTextIcon } from "@heroicons/react/24/outline"
import Pill from "../Pill"
import truncateUid from "../../utils/truncateUID";
import formatDate from "../../utils/formatDate";
import DataclipTypePill from "../DataclipTypePill";
import type { Dataclip } from "../types";

const iconStyle = 'h-4 w-4 text-grey-400';

interface SelectedClipViewProps {
  dataclip: Dataclip
  onUnselect: () => void
}

const SelectedClipView: React.FC<SelectedClipViewProps> = ({ dataclip, onUnselect }) => {
  return <>
    <div className="flex flex-col flex-0 px-4 gap-2">
      <Pill onClose={onUnselect}>
        <div className='flex px-2 py-1 grow items-center justify-between'>
          <div className="flex gap-1 items-center text-sm">
            {' '}
            <DocumentTextIcon
              className={`${iconStyle} group-hover:scale-110 group-hover:text-primary-600`}
            />{' '}
            {truncateUid(dataclip.id)}{' '}
          </div>
          <div className="text-xs truncate ml-2">
            {formatDate(new Date(dataclip.updated_at))}
          </div>
        </div>
      </Pill>
      <div className="flex flex-row">
        <div className="basis-1/2 font-medium text-secondary-700 text-sm">
          Type
        </div>
        <div className="basis-1/2 text-right">
          <DataclipTypePill type={dataclip.type} />
        </div>
      </div>
      <div className="flex flex-row">
        <div className="basis-1/2 font-medium text-secondary-700 text-sm">
          Created at
        </div>
        <div className="basis-1/2 text-right text-sm">
          {formatDate(new Date(dataclip.inserted_at))}
        </div>
      </div>
      <div className="flex flex-row">
        <div className="basis-1/2 font-medium text-secondary-700 text-sm">
          UUID:
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