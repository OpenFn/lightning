import { cn } from '#/utils/cn';

import { Tooltip } from '../../components/Tooltip';
import type { AISkill } from '../types/sessionContext';

export function SkillCommand({
  skill,
  className,
  withTooltip = true,
}: {
  skill: AISkill;
  className?: string;
  /** Off in an input, where the menu has just shown the description */
  withTooltip?: boolean;
}) {
  const command = (
    <span
      data-testid="skill-command"
      className={cn('text-primary-600', className)}
    >
      /{skill.name}
    </span>
  );

  return withTooltip ? (
    <Tooltip content={skill.description} side="top">
      {command}
    </Tooltip>
  ) : (
    command
  );
}
