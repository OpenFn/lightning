import type { AISkill } from '../types/sessionContext';

/**
 * Splits a message into the skill its leading `/name` invokes and the rest.
 * Mirrors Lightning.AiAssistant.Skills.detect/1, which decides what is sent.
 */
export function parseSlashCommand(
  content: string,
  skills: AISkill[]
): { skill: AISkill; rest: string } | null {
  const match = /^\/(\S+)(?:\s([\s\S]*))?$/.exec(content);
  if (!match) return null;

  const skill = skills.find(s => s.name === match[1]);
  return skill ? { skill, rest: match[2] ?? '' } : null;
}
