/**
 * YAMLCodeEditor - Textarea-based YAML editor
 *
 * Features:
 * - Monospace font for YAML editing
 * - Matches LiveView styling exactly
 * - Dark theme (slate-700 background, slate-200 text)
 */

interface YAMLCodeEditorProps {
  value: string;
  onChange: (value: string) => void;
  isValidating?: boolean;
}

export function YAMLCodeEditor({ value, onChange }: YAMLCodeEditorProps) {
  const handleChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    onChange(e.target.value);
  };

  return (
    <div className="h-full flex flex-col">
      <textarea
        id="yaml-editor"
        value={value}
        onChange={handleChange}
        placeholder="Paste your YAML content here"
        className="focus:outline focus:outline-2 focus:outline-offset-1 rounded-md shadow-xs text-sm block w-full h-full focus:ring-0 sm:text-sm sm:leading-6 phx-no-feedback:border-slate-300 phx-no-feedback:focus:border-slate-400 overflow-y-auto border-slate-300 focus:border-slate-400 focus:outline-primary-600 font-mono proportional-nums text-slate-200 bg-slate-700 resize-none text-nowrap overflow-x-auto"
      />
    </div>
  );
}
