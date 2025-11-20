import { cn } from '../utils/cn';

type DataclipType = 'step_result' | 'http_request' | 'global' | 'saved_input';

interface DataclipTypePillProps {
  type: DataclipType;
  size?: 'default' | 'small';
}

const DataclipTypePill: React.FC<DataclipTypePillProps> = ({
  type = 'saved_input',
  size = 'default',
}) => {
  const baseClasses = {
    default: 'px-2 py-1 rounded-full inline-block text-sm font-mono',
    small: 'px-1.5 py-0.5 rounded-full inline-block text-xs font-mono',
  }[size];

  const typeClasses =
    {
      step_result: 'bg-purple-500 text-purple-900',
      http_request: 'bg-green-500 text-green-900',
      global: 'bg-blue-500 text-blue-900',
      saved_input: 'bg-yellow-500 text-yellow-900',
    }[type] || '';

  return <div className={cn(baseClasses, typeClasses)}>{type}</div>;
};

export default DataclipTypePill;
