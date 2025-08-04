import React from 'react';
import type { WithActionProps } from '#/react/lib/with-props';
import type { CollaborativeEditorDataProps } from '../../types/todo';
import { SocketProvider } from '../contexts/SocketProvider';
import { TodoStoreProvider } from '../contexts/TodoStoreProvider';
import { TodoList } from './CollaborativeEditor/TodoList';
import { ConnectionStatus } from './CollaborativeEditor/ConnectionStatus';

export const CollaborativeEditor: WithActionProps<
  CollaborativeEditorDataProps
> = props => {
  // Extract data from props (ReactComponent hook passes data attributes as props)
  const workflowId = props['data-workflow-id'];
  const workflowName = props['data-workflow-name'];
  const userId = props['data-user-id'];
  const userName = props['data-user-name'];

  if (!workflowId || !userId || !userName) {
    return (
      <div className="collaborative-editor">
        <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg">
          <h3 className="text-lg font-semibold text-red-800 mb-2">
            ⚠️ Missing Required Data
          </h3>
          <div className="text-sm text-red-700">
            <p>workflowId: {workflowId || 'missing'}</p>
            <p>userId: {userId || 'missing'}</p>
            <p>userName: {userName || 'missing'}</p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="collaborative-editor">
      {/* Development info */}
      <div className="mb-6 p-4 bg-blue-50 border border-blue-200 rounded-lg">
        <h3 className="text-lg font-semibold text-blue-800 mb-2">
          🚀 Phoenix Channel Integration Active
        </h3>
        <div className="text-sm text-blue-700 space-y-1">
          <p>
            <strong>Workflow:</strong> {workflowName} ({workflowId})
          </p>
          <p>
            <strong>User:</strong> {userName} ({userId})
          </p>
          <p>
            <strong>Transport:</strong> Phoenix Channels (Binary Data)
          </p>
          <p>
            <strong>Status:</strong> Real-time CRDT collaboration ready
          </p>
        </div>
      </div>

      <SocketProvider>
        <TodoStoreProvider
          workflowId={workflowId}
          userId={userId}
          userName={userName}
        >
          <ConnectionStatus />
          <TodoList />
        </TodoStoreProvider>
      </SocketProvider>
    </div>
  );
};
