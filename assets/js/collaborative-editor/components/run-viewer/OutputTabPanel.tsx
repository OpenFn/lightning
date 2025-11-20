// TODO: Abstract InputTabPanel and OutputTabPanel into a single reusable
// DataclipTabPanel component that accepts a 'type' prop ("input" | "output")
// to handle both scenarios. The components share identical structure and logic,
// differing only in the dataclip field accessed (input_dataclip_id vs output_dataclip_id)
// and display text.

import { useMemo } from 'react';

import { DataclipViewer } from '../../../react/components/DataclipViewer';
import { useActiveRun, useSelectedStep } from '../../hooks/useHistory';
import type { StepDetail } from '../../types/history';
import { isFinalState } from '../../types/history';

interface OutputContentProps {
  selectedStep: StepDetail | null;
  runFinished: boolean;
}

function OutputContent({ selectedStep, runFinished }: OutputContentProps) {
  if (!selectedStep) {
    return (
      <div className="flex items-center justify-center h-full text-gray-500">
        Select a step to view output data
      </div>
    );
  }

  const hasDataclip = selectedStep.output_dataclip_id;

  if (!hasDataclip && runFinished) {
    return (
      <div className="text-center p-12 text-gray-500">
        No output state could be saved for this run.
      </div>
    );
  }

  if (!hasDataclip) {
    return <div className="text-center p-12 text-gray-500">Nothing yet</div>;
  }

  return <DataclipViewer dataclipId={hasDataclip} />;
}

export function OutputTabPanel() {
  const run = useActiveRun();
  const selectedStep = useSelectedStep();

  const runFinished = useMemo(
    () => !!(run?.state && isFinalState(run.state)),
    [run?.state]
  );

  return (
    <div className="h-full">
      <OutputContent selectedStep={selectedStep} runFinished={runFinished} />
    </div>
  );
}
