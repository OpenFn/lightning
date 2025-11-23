import { cn } from '#/utils/cn';

/**
 * MessageList Component
 *
 * Displays the list of messages in the AI Assistant chat.
 * Shows user and assistant messages with appropriate styling.
 *
 * Features:
 * - Empty state with welcome message
 * - User messages in bubble style (right-aligned)
 * - Assistant messages full-width with code blocks
 * - Loading and error states
 */

interface Message {
  id: string;
  content: string;
  role: 'user' | 'assistant';
  status: 'pending' | 'processing' | 'success' | 'error' | 'cancelled';
  code?: string;
  inserted_at: string;
}

interface MessageListProps {
  messages?: Message[];
}

export function MessageList({ messages = [] }: MessageListProps) {
  if (messages.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-full text-center px-4">
        <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-primary-50 to-primary-100 flex items-center justify-center mb-6">
          <img src="/images/logo.svg" alt="OpenFn" className="w-9 h-9" />
        </div>
        <h3 className="text-xl font-semibold text-gray-900 mb-2">
          How can I help you today?
        </h3>
        <p className="text-sm text-gray-600 max-w-md leading-relaxed">
          I can help you build workflows, write job code, debug errors, and
          answer questions about OpenFn adaptors.
        </p>
      </div>
    );
  }

  return (
    <div className="h-full overflow-y-auto">
      {messages.map(message => (
        <div
          key={message.id}
          className={cn(
            'group px-6 py-4',
            message.role === 'assistant' ? 'bg-gray-50/50' : 'bg-white'
          )}
        >
          <div className="max-w-3xl mx-auto">
            {message.role === 'assistant' ? (
              // Assistant Message - Full Width
              <div>
                {/* Message Content */}
                <div className="space-y-3">
                  {/* Message Text */}
                  <div className="text-[15px] text-gray-900 leading-7 whitespace-pre-wrap">
                    {message.content}
                  </div>

                  {/* Code Block - Only show for assistant messages */}
                  {message.code && (
                    <div className="rounded-lg overflow-hidden border border-gray-200 bg-white shadow-sm">
                      <div className="px-4 py-2 bg-gray-50 border-b border-gray-200 flex items-center justify-between">
                        <span className="text-xs font-medium text-gray-700">
                          Workflow YAML
                        </span>
                        <button
                          type="button"
                          className="text-xs text-gray-600 hover:text-gray-900 font-medium transition-colors"
                        >
                          Copy
                        </button>
                      </div>
                      <pre className="p-4 text-xs text-gray-900 overflow-x-auto font-mono leading-relaxed">
                        <code>{message.code}</code>
                      </pre>
                    </div>
                  )}

                  {/* Error State */}
                  {message.status === 'error' && (
                    <div className="flex items-center gap-2 px-3 py-2 rounded-lg bg-red-50 border border-red-200">
                      <span className="hero-exclamation-circle h-4 w-4 text-red-600 flex-shrink-0" />
                      <span className="text-sm text-red-700">
                        Failed to send message. Please try again.
                      </span>
                    </div>
                  )}

                  {/* Processing State */}
                  {message.status === 'processing' && (
                    <div className="flex items-center gap-2 text-gray-600">
                      <div className="flex items-center gap-1">
                        <span className="inline-block w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce" />
                        <span className="inline-block w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce [animation-delay:0.15s]" />
                        <span className="inline-block w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce [animation-delay:0.3s]" />
                      </div>
                    </div>
                  )}
                </div>
              </div>
            ) : (
              // User Message - Bubble Style
              <div className="flex justify-end">
                <div className="flex flex-col items-end max-w-[85%]">
                  <div className="rounded-2xl bg-gray-100 border border-gray-200 px-4 py-3">
                    <div className="text-[15px] text-gray-900 leading-6 whitespace-pre-wrap">
                      {message.content}
                    </div>
                  </div>

                  {/* Error State for User Messages */}
                  {message.status === 'error' && (
                    <div className="flex items-center gap-2 mt-2 px-3 py-1.5 rounded-lg bg-red-50 border border-red-200">
                      <span className="hero-exclamation-circle h-3.5 w-3.5 text-red-600" />
                      <span className="text-xs text-red-700">
                        Failed to send
                      </span>
                    </div>
                  )}
                </div>
              </div>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}
