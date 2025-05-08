import { XMarkIcon } from "@heroicons/react/24/outline";

interface PillProps {
  onClose: () => void;
}
const Pill: React.FC<React.PropsWithChildren<PillProps>> = ({ children, onClose }) => {
  return <div className="inline-flex justify-between items-center gap-x-0.5 rounded-md bg-blue-100 px-2 py-1 text-xs font-medium text-blue-700">
    {children}
    <button
      onClick={onClose}
      className="group relative -mr-1 h-3.5 w-3.5 rounded-sm hover:bg-blue-600/20"
    >
      <XMarkIcon />{' '}
    </button>
  </div>
}

export default Pill;