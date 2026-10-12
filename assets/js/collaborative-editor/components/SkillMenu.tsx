import { cn } from '#/utils/cn';

import type { AISkill } from '../types/sessionContext';

interface SkillMenuProps {
  id: string;
  matches: AISkill[];
  activeIndex: number;
  onChoose: (skill: AISkill) => void;
  onHighlight: (index: number) => void;
}

export function SkillMenu({
  id,
  matches,
  activeIndex,
  onChoose,
  onHighlight,
}: SkillMenuProps) {
  if (matches.length === 0) return null;

  return (
    <div
      id={id}
      role="listbox"
      aria-label="Skills"
      data-testid="skill-menu"
      className={cn(
        'absolute bottom-full left-0 right-0 mb-2 z-10 py-1',
        'rounded-lg border border-gray-200 bg-white shadow-lg'
      )}
    >
      {matches.map((s, i) => (
        <div
          key={s.name}
          id={`${id}-${s.name}`}
          role="option"
          aria-selected={i === activeIndex}
          tabIndex={-1}
          onMouseDown={e => {
            e.preventDefault();
            onChoose(s);
          }}
          onMouseEnter={() => onHighlight(i)}
          className={cn(
            'flex items-baseline gap-2 px-3 py-2 cursor-pointer',
            i === activeIndex && 'bg-gray-100'
          )}
        >
          <span className="text-sm font-medium text-gray-900">/{s.name}</span>
          <span className="text-xs text-gray-500 truncate">
            {s.description}
          </span>
        </div>
      ))}
    </div>
  );
}
