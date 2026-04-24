import { cn } from '../utils/cn';
import { Tooltip } from '../components/Tooltip';

interface PickerButtonProps {
  'data-label': string;
  /** Hero icon class for the button icon (e.g. `hero-folder`). */
  'data-icon': string;
  /**
   * Event dispatched on `document.body` when the button is clicked. The
   * matching Picker modal listens for this to open itself.
   */
  'data-open-event': string;

  // --- Project-picker-specific opt-in (ignored by other pickers) ---
  /** When `"true"`, renders in sandbox mode with colored background. */
  'data-is-sandbox'?: string | undefined;
  /** Accent-icon override used in sandbox mode (e.g. `hero-beaker`). */
  'data-accent-icon'?: string | undefined;
  /** Accent background color applied in sandbox mode. */
  'data-color'?: string | undefined;
}

/**
 * Generic picker trigger button. Shows a label with an icon; on click
 * dispatches a configured event that the corresponding Picker modal
 * listens for.
 *
 * The sandbox-specific styling (colored background, beaker icon,
 * deep-path truncation with tooltip) only activates when
 * `data-is-sandbox="true"`. Other pickers (e.g. billing) just set
 * label + icon + open-event and get a plain button.
 */
export function PickerButton(props: PickerButtonProps) {
  const label = props['data-label'] || '';
  const icon = props['data-icon'];
  const openEvent = props['data-open-event'];
  const isSandbox = props['data-is-sandbox'] === 'true';
  const accentIcon = props['data-accent-icon'] || icon;
  const color = props['data-color'] || null;

  const handleClick = (e: React.MouseEvent) => {
    e.preventDefault();
    document.body.dispatchEvent(new CustomEvent(openEvent));
  };

  const parts = label.split('/');
  const truncated = isSandbox && parts.length > 2;

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
          isSandbox ? `${accentIcon} text-white/80` : `${icon} text-gray-500`
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

  if (truncated) {
    return <Tooltip content={parts.join(' > ')}>{button}</Tooltip>;
  }

  return button;
}
