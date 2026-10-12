import { useLayoutEffect, useRef, useState } from 'react';
import type { KeyboardEvent, RefObject, UIEvent } from 'react';

import type { AISkill } from '../types/sessionContext';
import { parseSlashCommand } from '../utils/slashCommand';

/**
 * Slash-command state for a message textarea: the `/` menu, and the skill
 * pill a chosen command becomes. `content` is the message to send.
 */
export function useSlashCommand(
  skills: AISkill[],
  textareaRef: RefObject<HTMLTextAreaElement | null>
) {
  const [input, setInput] = useState('');
  const [skill, setSkill] = useState<AISkill | null>(null);
  const [highlighted, setHighlighted] = useState(0);
  const [dismissedMenuFor, setDismissedMenuFor] = useState<string | null>(null);
  const commandRef = useRef<HTMLSpanElement>(null);
  const [commandWidth, setCommandWidth] = useState(0);

  useLayoutEffect(() => {
    setCommandWidth(skill ? (commandRef.current?.offsetWidth ?? 0) : 0);
  }, [skill]);

  const content = skill
    ? `/${skill.name} ${input.trim()}`.trim()
    : input.trim();

  // A command is only one while it is the first token, so the menu closes
  // at the first whitespace.
  const matches =
    !skill && /^\/\S*$/.test(input) && dismissedMenuFor !== input
      ? skills.filter(s => s.name.startsWith(input.slice(1)))
      : [];
  const activeIndex = Math.min(highlighted, matches.length - 1);
  const activeSkill: AISkill | undefined = matches[activeIndex];
  const menuOpen = activeSkill !== undefined;

  const chooseSkill = (chosen: AISkill, rest = '') => {
    setSkill(chosen);
    setInput(rest);
    setHighlighted(0);
    textareaRef.current?.focus();
  };

  const handleChange = (value: string) => {
    // Typing the space after a known name, or pasting a whole command, turns
    // it into a pill; a bare `/qa` stays text until then, like `/qafoo`.
    const parsed = skill ? null : parseSlashCommand(value, skills);
    if (parsed && /^\/\S+\s/.test(value)) {
      chooseSkill(parsed.skill, parsed.rest);
      return;
    }
    setInput(value);
    setHighlighted(0);
  };

  /** Handles the menu and pill keys; true when the key was used. */
  const handleKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>): boolean => {
    if (activeSkill) {
      const move = { ArrowDown: 1, ArrowUp: -1 }[e.key];
      if (move) {
        e.preventDefault();
        setHighlighted((activeIndex + move + matches.length) % matches.length);
        return true;
      }
      if ((e.key === 'Enter' && !e.shiftKey) || e.key === 'Tab') {
        e.preventDefault();
        chooseSkill(activeSkill);
        return true;
      }
      if (e.key === 'Escape') {
        e.preventDefault();
        setDismissedMenuFor(input);
        return true;
      }
    }

    const { selectionStart, selectionEnd } = e.currentTarget;
    if (
      skill &&
      e.key === 'Backspace' &&
      selectionStart === 0 &&
      selectionEnd === 0
    ) {
      e.preventDefault();
      setSkill(null);
      return true;
    }

    return false;
  };

  const reset = () => {
    setInput('');
    setSkill(null);
  };

  return {
    input,
    skill,
    content,
    // The command is laid over the textarea's first line, so only that line
    // makes room for it and wrapped lines start at the left edge.
    commandRef,
    textIndent: commandWidth ? `calc(${commandWidth}px + 0.25em)` : undefined,
    onScroll: (e: UIEvent<HTMLTextAreaElement>) => {
      if (commandRef.current) {
        commandRef.current.style.transform = `translateY(-${e.currentTarget.scrollTop}px)`;
      }
    },
    handleChange,
    handleKeyDown,
    reset,
    comboboxProps: {
      role: 'combobox',
      'aria-expanded': menuOpen,
      'aria-controls': menuOpen ? 'skill-menu' : undefined,
      'aria-activedescendant':
        activeSkill && `skill-option-${activeSkill.name}`,
    },
    menuProps: {
      matches,
      activeIndex,
      onChoose: (s: AISkill) => chooseSkill(s),
      onHighlight: setHighlighted,
    },
  };
}
