import { useSyncExternalStore, useState, useMemo } from 'react';

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
 * - Search/filter sessions by title
 */
export function SessionList({
  store,
  onSessionSelect,
  currentSessionId,
}: SessionListProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [sortOrder, setSortOrder] = useState<'desc' | 'asc'>('desc');

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

  const filteredSessions = useMemo(() => {
    let filtered = sessionList;

    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase();
      filtered = filtered.filter(session =>
        session.title.toLowerCase().includes(query)
      );
    }

    const sorted = [...filtered].sort((a, b) => {
      const timeA = new Date(a.updated_at).getTime();
      const timeB = new Date(b.updated_at).getTime();

      if (sortOrder === 'desc') {
        return timeB - timeA;
      } else {
        return timeA - timeB;
      }
    });

    return sorted;
  }, [sessionList, searchQuery, sortOrder]);

  const handleLoadMore = () => {
    if (pagination && pagination.has_next_page) {
      void store.loadSessionList({
        offset: sessionList.length,
        limit: 20,
        append: true,
      });
    }
  };

  if (isLoading && sessionList.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-12 px-4">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-600 mb-3"></div>
        <p className="text-sm text-gray-500">Loading sessions...</p>
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
      <div className="flex-none px-6 pt-3 pb-2">
        <div className="flex items-center gap-2">
          <div className="relative flex-1">
            <span className="absolute left-3 top-1/2 -translate-y-1/2 hero-magnifying-glass h-4 w-4 text-gray-400" />
            <input
              type="text"
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
              placeholder="Search conversations..."
              className={cn(
                'w-full h-[34px] pl-9 pr-3 text-sm',
                'bg-gray-50 border border-gray-200 rounded-lg',
                'placeholder:text-gray-400',
                'focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent',
                'transition-all duration-200'
              )}
            />
            {searchQuery && (
              <button
                type="button"
                onClick={() => setSearchQuery('')}
                className="absolute right-2 top-1/2 -translate-y-1/2 p-1 rounded hover:bg-gray-200 transition-colors"
                aria-label="Clear search"
              >
                <span className="hero-x-mark h-3.5 w-3.5 text-gray-500" />
              </button>
            )}
          </div>

          <button
            type="button"
            onClick={() => setSortOrder(sortOrder === 'desc' ? 'asc' : 'desc')}
            className={cn(
              'flex-shrink-0 flex items-center gap-2 h-9 px-3 rounded-lg',
              'text-xs font-medium transition-all duration-200',
              'bg-gray-50',
              'text-gray-600 hover:bg-gray-100 hover:text-gray-900',
              'focus:outline-none'
            )}
          >
            <span
              className={cn(
                'transition-transform duration-300',
                sortOrder === 'desc' ? 'rotate-0' : 'rotate-180'
              )}
            >
              <span className="hero-arrow-down h-3.5 w-3.5" />
            </span>
            <span className="transition-all duration-200">
              {sortOrder === 'desc' ? 'Latest' : 'Oldest'}
            </span>
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto">
        {filteredSessions.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-12 px-4">
            <div className="hero-magnifying-glass h-12 w-12 text-gray-300 mb-3" />
            <p className="text-sm text-gray-500 text-center">
              No sessions found
            </p>
            <p className="text-xs text-gray-400 text-center mt-1">
              Try a different search term
            </p>
          </div>
        ) : (
          <div className="px-3 py-3 space-y-0.5">
            {filteredSessions.map(session => (
              <button
                key={session.id}
                data-testid="session-list-item"
                onClick={() => onSessionSelect(session.id)}
                className={cn(
                  'w-full text-left px-3 py-3 rounded-lg transition-all duration-200',
                  'focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-1',
                  'group relative',
                  session.id === currentSessionId
                    ? 'bg-primary-50 ring-1 ring-primary-200'
                    : 'hover:bg-gray-50 active:bg-gray-100'
                )}
              >
                {session.id === currentSessionId && (
                  <div className="absolute left-0 top-1/2 -translate-y-1/2 w-1 h-8 bg-primary-500 rounded-r-full" />
                )}

                <div className="min-w-0 flex-1 pr-0">
                  <h4
                    className={cn(
                      'text-sm font-medium truncate mb-1.5 leading-snug',
                      session.id === currentSessionId
                        ? 'text-gray-900'
                        : 'text-gray-700 group-hover:text-gray-900'
                    )}
                  >
                    {session.title}
                  </h4>

                  <div className="flex items-center justify-between gap-3">
                    <span
                      className={cn(
                        'text-xs tabular-nums',
                        session.id === currentSessionId
                          ? 'text-primary-600 font-medium'
                          : 'text-gray-500'
                      )}
                    >
                      {formatRelativeTime(session.updated_at)}
                    </span>
                    {session.message_count > 0 && (
                      <span
                        className={cn(
                          'flex-shrink-0 inline-flex items-center justify-center',
                          'min-w-[20px] h-5 px-1.5 rounded-full',
                          'text-xs font-medium tabular-nums',
                          session.id === currentSessionId
                            ? 'bg-primary-100 text-primary-700'
                            : 'bg-gray-100 text-gray-600 group-hover:bg-gray-200'
                        )}
                      >
                        {session.message_count}
                      </span>
                    )}
                  </div>
                </div>
              </button>
            ))}

            {pagination && pagination.has_next_page && (
              <button
                onClick={handleLoadMore}
                disabled={isLoading}
                className={cn(
                  'w-full px-3 py-2.5 text-xs font-medium rounded-lg',
                  'transition-all duration-200',
                  'focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-1',
                  isLoading
                    ? 'bg-gray-50 text-gray-400 cursor-not-allowed'
                    : 'text-gray-600 hover:bg-gray-50 hover:text-gray-900'
                )}
              >
                {isLoading ? (
                  <span className="flex items-center justify-center gap-2">
                    <span className="hero-arrow-path h-3.5 w-3.5 animate-spin" />
                    Loading...
                  </span>
                ) : (
                  <span className="flex items-center justify-center gap-2">
                    <span className="hero-chevron-down h-3.5 w-3.5" />
                    Load {pagination.total_count - sessionList.length} more
                  </span>
                )}
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

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
    return date.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
    });
  }
}
