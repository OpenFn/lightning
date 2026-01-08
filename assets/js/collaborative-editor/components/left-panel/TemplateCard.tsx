import { cn } from '#/utils/cn';

import type { Template } from '../../types/template';
import Badge from '../common/Badge';

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

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      handleClick();
    }
  };

  return (
    <div
      role="button"
      tabIndex={0}
      aria-pressed={isSelected}
      aria-label={`${template.name} template`}
      className={cn(
        'relative rounded-lg border p-3 cursor-pointer transition-all',
        'hover:border-primary-400 focus:outline-none',
        isSelected
          ? 'border-primary-500 bg-primary-50'
          : 'border-gray-200 bg-white'
      )}
      onClick={handleClick}
      onKeyDown={handleKeyDown}
    >
      <div
        className={cn(
          'flex items-start gap-2',
          !('isBase' in template && template.isBase) && 'mb-1'
        )}
      >
        <h3 className="text-sm font-medium text-gray-900 inline-flex flex-wrap items-center gap-x-1 gap-y-1">
          <span>{template.name}</span>
          {'isBase' in template && template.isBase && <Badge>base</Badge>}
        </h3>
        <div
          className={cn(
            'w-5 h-5 rounded-full border-2 transition-all ml-auto flex-shrink-0',
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
      {'isBase' in template && template.isBase ? null : (
        <p className="text-sm text-gray-600 line-clamp-2">
          {template.description || 'No description provided'}
        </p>
      )}
    </div>
  );
}
