import { DataclipViewer } from "../../../react/components/DataclipViewer";
import {
  useCurrentRun,
  useRunStoreInstance,
  useSelectedStep,
} from "../../hooks/useRun";
import { FINAL_STATES } from "../../types/run";
import { StepList } from "./StepList";

export function OutputTabPanel() {
  const run = useCurrentRun();
  const selectedStep = useSelectedStep();
  const runStore = useRunStoreInstance();

  if (!run) {
    return <div className="p-4 text-gray-500">No run selected</div>;
  }

  const runFinished = run.state && FINAL_STATES.includes(run.state as any);
  const hasDataclip = selectedStep?.output_dataclip_id;

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
        {!selectedStep ? (
          <div
            className="flex items-center justify-center
              h-full text-gray-500"
          >
            Select a step to view output data
          </div>
        ) : !hasDataclip && runFinished ? (
          <div className="text-center p-12 text-gray-500">
            No output state could be saved for this run.
          </div>
        ) : !hasDataclip ? (
          <div className="text-center p-12 text-gray-500">Nothing yet</div>
        ) : (
          <DataclipViewer dataclipId={selectedStep.output_dataclip_id!} />
        )}
      </div>
    </div>
  );
}
