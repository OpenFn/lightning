// TODO: Abstract InputTabPanel and OutputTabPanel into a single reusable
// DataclipTabPanel component that accepts a 'type' prop ("input" | "output")
// to handle both scenarios. The components share identical structure and logic,
// differing only in the dataclip field accessed (input_dataclip_id vs output_dataclip_id)
// and display text.

import { useMemo } from "react";

import { DataclipViewer } from "../../../react/components/DataclipViewer";
import {
  useCurrentRun,
  useRunStoreInstance,
  useSelectedStep,
} from "../../hooks/useRun";
import type { Step } from "../../types/run";
import { isFinalState } from "../../types/run";
import { StepList } from "./StepList";

interface OutputContentProps {
  selectedStep: Step | null;
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
  const run = useCurrentRun();
  const selectedStep = useSelectedStep();
  const runStore = useRunStoreInstance();

  const runFinished = useMemo(
    () => !!(run?.state && isFinalState(run.state)),
    [run?.state]
  );

  if (!run) {
    return <div className="p-4 text-gray-500">No run selected</div>;
  }

  return (
    <div className="h-full flex">
      {/* Step list */}
      <div className="w-48 border-r overflow-auto p-2">
        <StepList
          steps={run.steps}
          selectedStepId={selectedStep?.id || null}
          onSelectStep={runStore.selectStep}
        />
      </div>

      {/* Dataclip viewer */}
      <div className="flex-1 overflow-auto">
        <OutputContent selectedStep={selectedStep} runFinished={runFinished} />
      </div>
    </div>
  );
}
