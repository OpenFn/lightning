import { cn } from '#/utils/cn';

import type { Template } from '../../types/template';

interface TemplateCardProps {
  template: Template;
  isSelected: boolean;
  onClick: (template: Template) => void;
}

export function TemplateCard({
  template,
  isSelected,
  onClick,
}: TemplateCardProps) {
  const handleClick = () => {
    onClick(template);
  };

  return (
    <div
      className={cn(
        'relative rounded-lg border p-4 cursor-pointer transition-all',
        'hover:border-primary-400',
        isSelected
          ? 'border-primary-500 bg-primary-50'
          : 'border-gray-200 bg-white'
      )}
      onClick={handleClick}
    >
      <div className="absolute top-4 right-4">
        <div
          className={cn(
            'w-5 h-5 rounded-full border-2 transition-all',
            isSelected
              ? 'border-primary-500 bg-primary-500'
              : 'border-gray-300 bg-white'
          )}
        >
          {isSelected && (
            <div className="w-full h-full flex items-center justify-center">
              <div className="w-2 h-2 bg-white rounded-full" />
            </div>
          )}
        </div>
      </div>

      <h3 className="text-sm font-medium text-gray-900 mb-1 pr-6 truncate">
        {template.name}
      </h3>
      <p className="text-sm text-gray-600 line-clamp-2">
        {template.description || 'No description provided'}
      </p>
    </div>
  );
}
