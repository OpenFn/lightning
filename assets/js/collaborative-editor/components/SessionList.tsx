import { useSyncExternalStore } from 'react';

import { cn } from '#/utils/cn';

import type { AIAssistantStore } from '../types/ai-assistant';

interface SessionListProps {
  store: AIAssistantStore;
  onSessionSelect: (sessionId: string) => void;
  currentSessionId: string | null | undefined;
}

/**
 * SessionList Component
 *
 * Displays a list of user's AI assistant sessions with ability to switch
 * between them. Shows session metadata including title, message count,
 * and last updated time.
 *
 * Design inspired by ChatGPT sidebar:
 * - Chronological list of sessions
 * - Highlight active session
 * - Relative timestamps
 * - Message count badges
 * - Click to switch sessions
 */
export function SessionList({
  store,
  onSessionSelect,
  currentSessionId,
}: SessionListProps) {
  const sessionList = useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.sessionList)
  );

  const isLoading = useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.sessionListLoading)
  );

  const pagination = useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.sessionListPagination)
  );

  const handleLoadMore = () => {
    if (pagination && pagination.has_next_page) {
      const currentOffset = sessionList.length;
      store.loadSessionList(currentOffset);
    }
  };

  if (isLoading && sessionList.length === 0) {
    return (
      <div className="flex items-center justify-center py-8">
        <div className="text-sm text-gray-500">Loading sessions...</div>
      </div>
    );
  }

  if (sessionList.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-12 px-4">
        <div className="hero-chat-bubble-left-right h-12 w-12 text-gray-300 mb-3" />
        <p className="text-sm text-gray-500 text-center">No sessions yet</p>
        <p className="text-xs text-gray-400 text-center mt-1">
          Start a conversation to see it here
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full overflow-hidden bg-white">
      <div className="flex-1 overflow-y-auto">
        {/* Pagination info at top of scroll area */}
        {pagination && pagination.total_count > 0 && (
          <div className="sticky top-0 z-10 px-4 py-3 border-b border-gray-200 bg-white">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="text-xs text-gray-500 bg-gray-100 px-2 py-1 rounded-full">
                  {sessionList.length} of {pagination.total_count}
                </span>
              </div>
            </div>
          </div>
        )}

        <div className="space-y-0">
          {sessionList.map(session => (
            <button
              key={session.id}
              onClick={() => onSessionSelect(session.id)}
              className={cn(
                'w-full text-left px-4 py-4 transition-all border-b border-gray-100',
                'focus:outline-none',
                'group',
                session.id === currentSessionId
                  ? 'bg-primary-50 border-l-4 border-l-primary-500'
                  : 'hover:bg-gray-50 border-l-4 border-l-transparent'
              )}
            >
              <div className="min-w-0 flex-1">
                {/* Title and message count on same line */}
                <div className="flex items-baseline gap-2 mb-1.5">
                  <h4
                    className={cn(
                      'text-[15px] font-medium truncate flex-1',
                      session.id === currentSessionId
                        ? 'text-gray-900'
                        : 'text-gray-900'
                    )}
                  >
                    {session.title}
                  </h4>
                  {session.message_count > 0 && (
                    <span
                      className={cn(
                        'flex-shrink-0 text-xs font-medium tabular-nums',
                        session.id === currentSessionId
                          ? 'text-primary-600'
                          : 'text-gray-500'
                      )}
                    >
                      {session.message_count}
                    </span>
                  )}
                </div>

                {/* Timestamp */}
                <div className="flex items-center gap-1.5">
                  <span
                    className={cn(
                      'hero-clock h-3.5 w-3.5 flex-shrink-0',
                      session.id === currentSessionId
                        ? 'text-primary-500'
                        : 'text-gray-400'
                    )}
                  />
                  <p
                    className={cn(
                      'text-xs',
                      session.id === currentSessionId
                        ? 'text-primary-600'
                        : 'text-gray-500'
                    )}
                  >
                    {formatRelativeTime(session.updated_at)}
                  </p>
                </div>
              </div>
            </button>
          ))}

          {/* Load More Button */}
          {pagination && pagination.has_next_page && (
            <div className="px-4 py-4 border-t border-gray-100">
              <button
                onClick={handleLoadMore}
                disabled={isLoading}
                className={cn(
                  'w-full px-4 py-2.5 text-sm font-medium rounded-lg',
                  'border border-gray-300 transition-all',
                  isLoading
                    ? 'bg-gray-50 text-gray-400 cursor-not-allowed'
                    : 'bg-white text-gray-700 hover:bg-gray-50 hover:border-gray-400'
                )}
              >
                {isLoading ? (
                  <span className="flex items-center justify-center gap-2">
                    <span className="hero-arrow-path h-4 w-4 animate-spin" />
                    Loading...
                  </span>
                ) : (
                  <span className="flex items-center justify-center gap-2">
                    <span className="hero-chevron-down h-4 w-4" />
                    Load more ({pagination.total_count -
                      sessionList.length}{' '}
                    remaining)
                  </span>
                )}
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

/**
 * Format timestamp as relative time (e.g., "2 hours ago")
 */
function formatRelativeTime(timestamp: string): string {
  const date = new Date(timestamp);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffSec = Math.floor(diffMs / 1000);
  const diffMin = Math.floor(diffSec / 60);
  const diffHour = Math.floor(diffMin / 60);
  const diffDay = Math.floor(diffHour / 24);

  if (diffSec < 60) {
    return 'just now';
  } else if (diffMin < 60) {
    return `${diffMin} ${diffMin === 1 ? 'minute' : 'minutes'} ago`;
  } else if (diffHour < 24) {
    return `${diffHour} ${diffHour === 1 ? 'hour' : 'hours'} ago`;
  } else if (diffDay < 7) {
    return `${diffDay} ${diffDay === 1 ? 'day' : 'days'} ago`;
  } else {
    // Format as date for older sessions
    return date.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
    });
  }
}
