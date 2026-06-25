import { useState } from 'react';

import { cn } from '#/utils/cn';

interface WorkflowOptionCardProps {
  icon: string;
  title: string;
  description: string;
  onClick: () => void;
  testId: string;
}

interface LandingScreenProps {
  aiAssistantEnabled: boolean;
  onBuildWithAI: (prompt: string) => void;
  onBuildFromScratch: () => void;
  onBrowseTemplates: () => void;
  onImportYAML: () => void;
}

export function LandingScreen({
  aiAssistantEnabled,
  onBuildWithAI,
  onBuildFromScratch,
  onBrowseTemplates,
  onImportYAML,
}: LandingScreenProps) {
  const [prompt, setPrompt] = useState('');
  const isValid = prompt.trim().length > 0;

  const handleSubmit = () => {
    if (!isValid) return;
    onBuildWithAI(prompt);
  };

  return (
    <div
      role="region"
      aria-labelledby="landing-screen-heading"
      className="absolute inset-0 z-10 flex items-center justify-center"
      data-testid="landing-screen"
    >
      <div className="w-full md:max-w-xl flex flex-col gap-6 px-6 lg:px-2">
        <h1
          id="landing-screen-heading"
          className="text-3xl font-semibold text-gray-900"
        >
          Where would you like to start today?
        </h1>

        {aiAssistantEnabled && (
          <div className="flex flex-col gap-2">
            <div className="flex items-center gap-2">
              <label
                htmlFor="build-with-ai-input"
                className="text-sm font-semibold text-gray-900"
              >
                Build with AI
              </label>
              <span className="text-semantic-success flex gap-2 items-center px-3 py-1 bg-surface-subtle rounded-lg text-xs font-medium">
                {/* Custom sparkle — no heroicons equivalent */}
                <svg
                  aria-hidden="true"
                  width="10"
                  height="10"
                  viewBox="0 0 10 10"
                  fill="currentColor"
                  xmlns="http://www.w3.org/2000/svg"
                >
                  <path d="M5 0 C5 0 5.5 4 10 5 C5.5 6 5 10 5 10 C5 10 4.5 6 0 5 C4.5 4 5 0 5 0 Z" />
                </svg>
                <span>Recommended</span>
              </span>
            </div>
            <div className="rounded-lg border border-border-subtle bg-white focus-within:ring focus-within:ring-gray-300 transition-shadow">
              <textarea
                // eslint-disable-next-line jsx-a11y/no-autofocus
                autoFocus
                id="build-with-ai-input"
                data-testid="build-with-ai-input"
                aria-describedby="build-with-ai-hint"
                value={prompt}
                onChange={e => setPrompt(e.target.value)}
                onKeyDown={e => {
                  if (e.key === 'Enter' && !e.shiftKey && !e.altKey) {
                    e.preventDefault();
                    handleSubmit();
                  }
                }}
                placeholder="e.g. Sync new KoboToolbox submissions into Postgres"
                rows={4}
                className="w-full rounded-t-lg border-none px-3 py-3 text-sm text-gray-900 placeholder:text-gray-400 focus:outline-none focus:ring-0 resize-none bg-transparent"
              />
              <span id="build-with-ai-hint" className="sr-only">
                Press Enter to submit. Use Shift+Enter or Alt+Enter for a new
                line.
              </span>
              <div className="flex justify-end px-3 py-2">
                <button
                  data-testid="build-with-ai-button"
                  type="button"
                  onClick={handleSubmit}
                  disabled={!isValid}
                  className="text-sm flex items-center gap-2 text-black hover:text-gray-700 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  Build it
                  <span className="hero-arrow-right h-4 w-4 stroke-4"></span>
                </button>
              </div>
            </div>
          </div>
        )}

        <div className="grid md:grid-cols-2 gap-4">
          <WorkflowOptionCard
            testId="build-from-scratch-card"
            icon="hero-plus-circle"
            title="Build from scratch"
            description="Start with an empty canvas and pick a trigger as your first step."
            onClick={onBuildFromScratch}
          />
          <WorkflowOptionCard
            testId="browse-templates-card"
            icon="hero-document-plus"
            title="Browse templates"
            description="Start from a published workflow template and adapt it."
            onClick={onBrowseTemplates}
          />
        </div>

        <p className="text-sm text-center text-gray-500">
          or{' '}
          <button
            type="button"
            data-testid="import-yaml-link"
            onClick={onImportYAML}
            className="underline hover:text-gray-700 transition-colors"
          >
            import a YAML file manually
          </button>
        </p>
      </div>
    </div>
  );
}

function WorkflowOptionCard({
  icon,
  title,
  description,
  onClick,
  testId,
}: WorkflowOptionCardProps) {
  return (
    <button
      data-testid={testId}
      type="button"
      onClick={onClick}
      className="rounded-xl flex flex-col border border-border-subtle bg-white p-5 text-left hover:border-gray-300 hover:bg-gray-50 transition-colors focus:outline-none focus-visible:ring focus-visible:ring-gray-300"
    >
      <span className="w-fit inline-flex items-center justify-center rounded-lg bg-gray-100 p-2 mb-3">
        <span className={cn('h-5 w-5 text-gray-700', icon)} />
      </span>
      <p className="text-sm font-semibold text-gray-900">{title}</p>
      <p className="mt-1 text-sm text-gray-600">{description}</p>
    </button>
  );
}
