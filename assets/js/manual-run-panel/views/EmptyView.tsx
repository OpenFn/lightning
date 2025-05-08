import { InformationCircleIcon } from "@heroicons/react/24/outline";

const EmptyView: React.FC = () => {
  return (
    <div className="flex justify-center gap-1 text-sm py-5">
      <InformationCircleIcon className={`h-5 w-5 text-yellow-600 pb-[1px]`} />
      An empty object will be used as input to this run.
    </div>
  );
};
export default EmptyView;