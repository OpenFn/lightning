import type { Workflow } from "../../types/workflow";

interface WorkflowSettingsProps {
  workflow: Workflow;
}

export function WorkflowSettings({ workflow }: WorkflowSettingsProps) {
  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-sm font-medium text-gray-900 mb-4">
          Workflow Name
        </h3>
        <input
          type="text"
          defaultValue={workflow.name}
          className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
        />
      </div>

      <div>
        <h3 className="text-sm font-medium text-gray-900 mb-2">
          Workflow as YAML
        </h3>
        <button
          type="button"
          className="text-sm text-indigo-600 hover:text-indigo-500"
        >
          View your workflow as YAML code
        </button>
      </div>

      <div>
        <h3 className="text-sm font-medium text-gray-900 mb-2">Log Output</h3>
        <p className="text-sm text-gray-600 mb-3">
          Control what's printed in run logs
        </p>
        <label className="flex items-center space-x-3">
          <span className="text-sm text-gray-900">
            Allow console.log() usage
          </span>
          <div className="relative">
            <input type="checkbox" defaultChecked={true} className="sr-only" />
            <div className="w-11 h-6 bg-indigo-600 rounded-full relative transition-colors">
              <div className="absolute right-1 top-1 w-4 h-4 bg-white rounded-full flex items-center justify-center">
                <div className="hero-check w-3 h-3 text-indigo-600" />
              </div>
            </div>
          </div>
        </label>
      </div>

      <div>
        <h3 className="text-sm font-medium text-gray-900 mb-2">Concurrency</h3>
        <p className="text-sm text-gray-600 mb-3">
          Control how many of this workflow's <em>Runs</em> are executed at the
          same time
        </p>
        <div>
          <label className="flex items-center space-x-2 mb-2">
            <span className="text-sm text-gray-900">Max Concurrency</span>
            <div className="w-4 h-4 bg-gray-400 rounded-full flex items-center justify-center">
              <span className="text-xs text-white font-bold">i</span>
            </div>
          </label>
          <input
            type="text"
            className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
          />
          <p className="text-xs text-gray-500 mt-1 italic">
            Unlimited (up to max available)
          </p>
        </div>
      </div>
    </div>
  );
}
