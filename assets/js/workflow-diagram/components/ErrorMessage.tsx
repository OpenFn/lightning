import { ExclamationCircleIcon } from '@heroicons/react/24/outline';

const ErrorMessage: React.FC<{ children?: React.ReactNode }> = ({
  children,
}) => {
  return (
    <p className="line-clamp-2 align-left text-xs text-red-500 flex items-center">
      <ExclamationCircleIcon className="mr-1 w-5" />
      {children ?? 'An error occurred'}
    </p>
  );
};

export default ErrorMessage;
