type DataclipType = 'step_result' | 'http_request' | 'global' | 'saved_input';

interface DataclipTypePillProps {
  type: DataclipType;
}

const DataclipTypePill: React.FC<DataclipTypePillProps> = ({
  type = 'saved_input',
}) => {
  const baseClasses = 'px-2 py-1 rounded-full inline-block text-sm font-mono';

  const typeClasses =
    {
      step_result: 'bg-purple-500 text-purple-900',
      http_request: 'bg-green-500 text-green-900',
      global: 'bg-blue-500 text-blue-900',
      saved_input: 'bg-yellow-500 text-yellow-900',
    }[type] || '';

  return <div className={`${baseClasses} ${typeClasses}`}>{type}</div>;
};

export default DataclipTypePill