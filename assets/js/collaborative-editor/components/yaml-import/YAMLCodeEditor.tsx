/**
 * YAMLCodeEditor - Textarea-based YAML editor
 *
 * Features:
 * - Monospace font for YAML editing
 * - Auto-growing textarea
 * - Syntax highlighting via CSS (basic)
 */

interface YAMLCodeEditorProps {
  value: string;
  onChange: (value: string) => void;
  isValidating?: boolean;
}

export function YAMLCodeEditor({
  value,
  onChange,
  isValidating = false,
}: YAMLCodeEditorProps) {
  const handleChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    onChange(e.target.value);
  };

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <label
          htmlFor="yaml-editor"
          className="block text-sm font-medium text-gray-700"
        >
          Paste YAML Content
        </label>
        {isValidating && (
          <span className="text-xs text-gray-500">Validating...</span>
        )}
      </div>
      <textarea
        id="yaml-editor"
        value={value}
        onChange={handleChange}
        placeholder={`name: My Workflow
jobs:
  fetch-data:
    name: Fetch Data
    adaptor: '@openfn/language-http@latest'
    body: |
      get('/api/data')

triggers:
  webhook:
    type: webhook
    enabled: true

edges:
  webhook->fetch-data:
    source_trigger: webhook
    target_job: fetch-data
    condition_type: always
    enabled: true`}
        className="w-full h-96 px-3 py-2 border border-gray-300 rounded-lg shadow-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 font-mono text-sm resize-vertical"
        style={{ minHeight: '384px' }}
      />
      <p className="text-xs text-gray-500">
        Enter or paste your workflow YAML here. The content will be validated in
        real-time.
      </p>
    </div>
  );
}
