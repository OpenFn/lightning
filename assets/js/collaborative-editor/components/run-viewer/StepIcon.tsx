interface StepIconProps {
  exitReason: string | null;
  errorType: string | null;
}

// Ported from lib/lightning_web/live/run_live/components.ex:504-555
// Matches the LiveView step_icon implementation exactly
export function StepIcon({ exitReason, errorType }: StepIconProps) {
  // Note: mr-1.5 and inline are intentionally omitted here as they're context-dependent
  // The parent component should handle spacing
  const iconClass = 'h-5 w-5 flex-shrink-0';
  let colorClass = '';
  let IconComponent: string;

  if (!exitReason) {
    IconComponent = 'hero-ellipsis-horizontal-circle-solid';
    colorClass = 'text-gray-400';
  } else if (exitReason === 'success') {
    IconComponent = 'hero-check-circle-solid';
    colorClass = 'text-green-500';
  } else if (exitReason === 'fail') {
    IconComponent = 'hero-x-circle-solid';
    colorClass = 'text-red-500';
  } else if (exitReason === 'crash') {
    IconComponent = 'hero-x-circle-solid';
    colorClass = 'text-orange-800';
  } else if (exitReason === 'cancel') {
    IconComponent = 'hero-no-symbol-solid';
    colorClass = 'text-gray-600';
  } else if (exitReason === 'kill' && errorType === 'SecurityError') {
    IconComponent = 'hero-shield-exclamation-solid';
    colorClass = 'text-yellow-800';
  } else if (exitReason === 'kill' && errorType === 'ImportError') {
    IconComponent = 'hero-shield-exclamation-solid';
    colorClass = 'text-yellow-800';
  } else if (exitReason === 'kill' && errorType === 'TimeoutError') {
    IconComponent = 'hero-clock-solid';
    colorClass = 'text-yellow-800';
  } else if (exitReason === 'kill' && errorType === 'OOMError') {
    IconComponent = 'hero-exclamation-circle-solid';
    colorClass = 'text-yellow-800';
  } else if (exitReason === 'exception') {
    // Note: Elixir checks for empty string errorType, but this matches the behavior
    // text-black-800 in Elixir is invalid; using text-black to match visual intent
    IconComponent = 'hero-exclamation-triangle-solid';
    colorClass = 'text-black';
  } else if (exitReason === 'lost') {
    IconComponent = 'hero-exclamation-triangle-solid';
    colorClass = 'text-black';
  } else {
    // Fallback for unknown exit reasons (not in original Elixir version)
    IconComponent = 'hero-ellipsis-horizontal-circle-solid';
    colorClass = 'text-gray-400';
  }

  return <span className={`${IconComponent} ${iconClass} ${colorClass}`} />;
}
