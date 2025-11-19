import type { StepDetail } from '../../types/history';

import { StepItem } from './StepItem';

interface StepListProps {
  steps: StepDetail[];
  selectedStepId: string | null;
  onSelectStep: (stepId: string) => void;
}

export function StepList({
  steps,
  selectedStepId,
  onSelectStep,
}: StepListProps) {
  if (steps.length === 0) {
    return <div className="text-center text-gray-500 py-4">No steps yet</div>;
  }

  return (
    <ul role="list" aria-label="Execution steps" className="space-y-2">
      {steps.map(step => (
        <li key={step.id}>
          <StepItem
            step={step}
            selected={step.id === selectedStepId}
            onSelect={() => onSelectStep(step.id)}
          />
        </li>
      ))}
    </ul>
  );
}
