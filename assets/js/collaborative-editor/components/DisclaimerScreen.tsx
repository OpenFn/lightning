/**
 * DisclaimerScreen Component
 *
 * Full-screen onboarding disclaimer shown before first use of AI Assistant.
 * Matches the design of the loading screen with OpenFn logo and AI Assistant branding.
 *
 * User must acknowledge the disclaimer before using the AI Assistant.
 */

interface DisclaimerScreenProps {
  onAccept: () => void;
  disabled?: boolean;
}

export function DisclaimerScreen({
  onAccept,
  disabled = false,
}: DisclaimerScreenProps) {
  return (
    <div className="h-full flex flex-col items-center justify-center px-8 py-12 bg-white">
      <div className="max-w-lg text-center space-y-8">
        {/* Logo + Title */}
        <div className="flex items-center justify-center gap-3">
          <img src="/images/logo.svg" alt="OpenFn" className="h-12 w-12" />
          <h2 className="text-2xl font-semibold text-gray-900">Assistant</h2>
        </div>

        {/* Main description */}
        <div className="space-y-4 text-gray-700 leading-relaxed">
          <p className="text-base">
            The Assistant helps you design and build your workflows by
            understanding your requirements and generating working
            implementations.
          </p>

          <p className="text-base font-medium text-gray-900">
            You are responsible for reviewing and testing all AI-generated code
            before use.
          </p>
        </div>

        {/* CTA Button */}
        <div className="pt-2">
          <button
            onClick={onAccept}
            disabled={disabled}
            className="w-full px-8 py-3.5 bg-indigo-600 hover:bg-indigo-700 disabled:bg-gray-300 disabled:cursor-not-allowed text-white text-base font-semibold rounded-lg transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 shadow-sm hover:shadow-md"
          >
            Get started
          </button>
        </div>

        {/* Disclaimers */}
        <div className="text-sm text-gray-600 space-y-3 pt-4 border-t border-gray-200">
          <p className="font-medium text-gray-900">
            Do not include real user data, personally identifiable information,
            or sensitive credentials in your messages.
          </p>
          <p className="text-xs text-gray-500">
            This Assistant uses Claude by Anthropic. Messages are stored on
            OpenFn servers and temporarily on Anthropic servers (up to 30 days)
            but are not used to train AI models.{' '}
            <a
              href="https://privacy.claude.com/en/collections/10672411-data-handling-retention"
              target="_blank"
              rel="noopener noreferrer"
              className="text-indigo-600 hover:text-indigo-700 underline"
            >
              Read more about this here
            </a>
            .
          </p>
        </div>
      </div>
    </div>
  );
}
