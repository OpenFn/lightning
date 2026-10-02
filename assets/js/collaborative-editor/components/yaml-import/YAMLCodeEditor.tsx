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

// v2 (CLI-aligned portability format) example shown when the editor is
// empty. Both v1 (legacy `jobs:`/`triggers:`/`edges:` maps) and v2 (unified
// `steps:` array) are accepted by the importer; the v2 shape matches what
// canvas Code panel exports and what `@openfn/cli` writes.
const PLACEHOLDER_EXAMPLE = `# Paste your workflow YAML here, for example:
#
# name: My Workflow
# steps:
#   - id: webhook
#     type: webhook
#     webhook_reply: before_start
#     enabled: true
#     next:
#       say-hello:
#         condition: always
#   - id: say-hello
#     name: Say Hello
#     adaptor: '@openfn/language-common@latest'
#     expression: |
#       fn(state => {
#         console.log("Hello, world!");
#         return state;
#       })
`;

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
        placeholder={PLACEHOLDER_EXAMPLE}
        className="focus:outline focus:outline-2 focus:outline-offset-1 rounded-md shadow-xs text-sm block w-full h-full focus:ring-0 sm:text-sm sm:leading-6 overflow-y-auto border-slate-300 focus:border-slate-400 focus:outline-primary-600 font-mono proportional-nums text-slate-200 bg-slate-700 resize-none text-nowrap overflow-x-auto"
      />
    </div>
  );
}
