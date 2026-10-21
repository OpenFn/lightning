import type { editor, IRange } from 'monaco-editor';

import type { AddedRun } from './workflowDiff';

type SearchableModel = Pick<
  editor.ITextModel,
  'findMatches' | 'getLineMaxColumn'
>;

/**
 * Where each added run sits in the editor now. Found by exact text, so a run
 * that has moved is still found but one edited since is not. Of several
 * whole-line copies, the one nearest the run's original line wins; a run of
 * only blank lines is skipped.
 */
export const locateAddedRuns = (
  model: SearchableModel,
  added: AddedRun[]
): IRange[] =>
  added.flatMap(({ line, text }) => {
    if (!text.trim()) return [];
    const whole = model
      .findMatches(text, false, false, true, null, false)
      .map(match => match.range)
      .filter(
        range =>
          range.startColumn === 1 &&
          range.endColumn === model.getLineMaxColumn(range.endLineNumber)
      );
    const nearest = whole.sort(
      (a, b) =>
        Math.abs(a.startLineNumber - line) - Math.abs(b.startLineNumber - line)
    )[0];
    return nearest ? [nearest] : [];
  });
