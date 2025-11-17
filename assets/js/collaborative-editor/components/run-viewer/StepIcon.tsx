interface StepIconProps {
  exitReason: string | null;
  errorType: string | null;
}

// Ported from lib/lightning_web/live/run_live/components.ex:510-524
export function StepIcon({ exitReason, errorType }: StepIconProps) {
  const iconClass = 'size-5 flex-shrink-0';
  let colorClass = '';
  let IconComponent: string;

  if (!exitReason) {
    IconComponent = 'hero-ellipsis-horizontal-circle';
    colorClass = 'text-gray-400';
  } else if (exitReason === 'success') {
    IconComponent = 'hero-check-circle';
    colorClass = 'text-green-500';
  } else if (exitReason === 'fail') {
    IconComponent = 'hero-x-circle';
    colorClass = 'text-red-500';
  } else if (exitReason === 'crash') {
    IconComponent = 'hero-x-circle';
    colorClass = 'text-orange-800';
  } else if (exitReason === 'cancel') {
    IconComponent = 'hero-no-symbol';
    colorClass = 'text-gray-600';
  } else if (exitReason === 'kill' && errorType === 'SecurityError') {
    IconComponent = 'hero-shield-exclamation';
    colorClass = 'text-yellow-800';
  } else if (exitReason === 'kill' && errorType === 'ImportError') {
    IconComponent = 'hero-shield-exclamation';
    colorClass = 'text-yellow-800';
  } else if (exitReason === 'kill' && errorType === 'TimeoutError') {
    IconComponent = 'hero-clock';
    colorClass = 'text-yellow-800';
  } else if (exitReason === 'kill' && errorType === 'OOMError') {
    IconComponent = 'hero-exclamation-circle';
    colorClass = 'text-yellow-800';
  } else if (exitReason === 'exception') {
    IconComponent = 'hero-exclamation-triangle';
    colorClass = 'text-black';
  } else if (exitReason === 'lost') {
    IconComponent = 'hero-exclamation-triangle';
    colorClass = 'text-black';
  } else {
    IconComponent = 'hero-question-mark-circle';
    colorClass = 'text-gray-400';
  }

  return <span className={`${IconComponent} ${iconClass} ${colorClass}`} />;
}
