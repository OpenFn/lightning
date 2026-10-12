import { Tooltip } from '../../components/Tooltip';
import type { AISkill } from '../types/sessionContext';

export function SkillCommand({
  skill,
  withTooltip = true,
}: {
  skill: AISkill;
  /** Off in an input, where the menu has just shown the description */
  withTooltip?: boolean;
}) {
  const command = (
    <span data-testid="skill-command" className="text-primary-600">
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
