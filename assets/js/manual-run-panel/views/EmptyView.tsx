import { InformationCircleIcon } from "@heroicons/react/24/outline";

const EmptyView: React.FC = () => {
  return (
    <div className="h-16 p-4">
      <div className="text-gray-500 pb-2 justify-center flex gap-1">
        <div className="flex mt-0.5"><InformationCircleIcon className={`h-5 w-5 text-yellow-600 pb-[1px]`} /></div>
        An empty object will be used as the input for this run.
      </div>
    </div>
  );
};
export default EmptyView;