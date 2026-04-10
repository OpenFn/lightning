import { cn } from '../utils/cn';
import { Tooltip } from '../collaborative-editor/components/Tooltip';

interface ProjectPickerButtonProps {
  'data-label': string;
  'data-is-sandbox'?: string | undefined;
  'data-color'?: string | undefined;
}

/**
 * Project picker trigger button.
 *
 * Mounted via ReactComponent hook in HEEx layouts and used directly
 * in the collaborative editor. Clicking dispatches `open-project-picker`
 * on document.body, which the global ProjectPicker modal listens for.
 */
export function ProjectPickerButton(props: ProjectPickerButtonProps) {
  const label = props['data-label'] || '';
  const isSandbox = props['data-is-sandbox'] === 'true';
  const color = props['data-color'] || null;

  const handleClick = (e: React.MouseEvent) => {
    e.preventDefault();
    document.body.dispatchEvent(new CustomEvent('open-project-picker'));
  };

  const parts = label.split('/');
  const truncated = isSandbox && parts.length > 2;
  const showTooltip = truncated;

  const button = (
    <button
      type="button"
      onClick={handleClick}
      className={cn(
        'flex items-center gap-2 px-2.5 py-1.5 text-sm font-medium rounded-md cursor-pointer transition-colors',
        !isSandbox &&
          'text-gray-700 bg-white border border-gray-300 hover:bg-gray-50 hover:border-gray-400',
        isSandbox && 'text-white border border-transparent hover:opacity-90'
      )}
      style={isSandbox && color ? { backgroundColor: color } : undefined}
    >
      <span
        className={cn(
          'h-4 w-4',
          isSandbox ? 'hero-beaker text-white/80' : 'hero-folder text-gray-500'
        )}
      />
      <span>
        {isSandbox && parts.length > 1
          ? (() => {
              const visible = truncated ? parts.slice(-2) : parts;
              return (
                <>
                  {truncated && <span className="opacity-50">…</span>}
                  {visible.map((part, i) => (
                    <span key={i}>
                      {(i > 0 || truncated) && <span>:</span>}
                      {part}
                    </span>
                  ))}
                </>
              );
            })()
          : label}
      </span>
      <span
        className={cn(
          'hero-chevron-down h-4 w-4 shrink-0',
          isSandbox ? 'text-white/80' : 'text-gray-400'
        )}
      />
    </button>
  );

  if (showTooltip) {
    return <Tooltip content={parts.join(' > ')}>{button}</Tooltip>;
  }

  return button;
}
