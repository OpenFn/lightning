import { cn } from '#/utils/cn';

import { Tooltip } from '../../components/Tooltip';
import type { AISkill } from '../types/sessionContext';

export function SkillCommand({
  skill,
  className,
}: {
  skill: AISkill;
  className?: string;
}) {
  return (
    <Tooltip content={skill.description} side="top">
      <span
        data-testid="skill-command"
        className={cn('text-primary-600', className)}
      >
        /{skill.name}
      </span>
    </Tooltip>
  );
}
