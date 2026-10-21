import { describe, it, expect } from 'vitest';

import { locateAddedRuns } from '../../../js/collaborative-editor/utils/locateAddedRuns';

// Stands in for Monaco's exact, case-sensitive findMatches over plain text
const fakeModel = (body: string) => {
  const lines = body.split('\n');
  const offsetToPosition = (offset: number) => {
    const before = body.slice(0, offset).split('\n');
    return {
      lineNumber: before.length,
      column: before[before.length - 1].length + 1,
    };
  };
  return {
    getLineMaxColumn: (line: number) => lines[line - 1].length + 1,
    findMatches: (search: string) => {
      const matches = [];
      for (
        let i = body.indexOf(search);
        i !== -1;
        i = body.indexOf(search, i + 1)
      ) {
        const start = offsetToPosition(i);
        const end = offsetToPosition(i + search.length);
        matches.push({
          range: {
            startLineNumber: start.lineNumber,
            startColumn: start.column,
            endLineNumber: end.lineNumber,
            endColumn: end.column,
          },
        });
      }
      return matches;
    },
  } as unknown as Parameters<typeof locateAddedRuns>[0];
};

const startLines = (ranges: ReturnType<typeof locateAddedRuns>) =>
  ranges.map(range => [range.startLineNumber, range.endLineNumber]);

describe('locateAddedRuns', () => {
  it('finds a multi-line run that has moved since the reply', () => {
    const model = fakeModel(
      '// new header\n\nfn(state => {\n  return state;\n});'
    );
    const ranges = locateAddedRuns(model, [
      { line: 1, text: 'fn(state => {\n  return state;\n});' },
    ]);
    expect(startLines(ranges)).toEqual([[3, 5]]);
  });

  it('finds nothing for a run edited since the reply', () => {
    const model = fakeModel("get('/patients');");
    const ranges = locateAddedRuns(model, [
      { line: 1, text: "get('/Patients');" },
    ]);
    expect(ranges).toEqual([]);
  });

  it('picks the copy nearest the original line', () => {
    const model = fakeModel('return state;\nx;\nx;\nx;\nreturn state;');
    const ranges = locateAddedRuns(model, [{ line: 4, text: 'return state;' }]);
    expect(startLines(ranges)).toEqual([[5, 5]]);
  });

  it('ignores partial-line matches and blank runs', () => {
    const model = fakeModel('  return state;\n\n');
    const ranges = locateAddedRuns(model, [
      { line: 1, text: 'return state;' },
      { line: 2, text: '\n' },
    ]);
    expect(ranges).toEqual([]);
  });
});
