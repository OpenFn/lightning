import { useEffect } from 'react';
import type { WithActionProps } from '#/react/lib/with-props';
import type { CollaborativeEditorDataProps } from '../../types/todo';
import { useTodoStore } from '../../stores/todo-store';
import { TodoList } from './CollaborativeEditor/TodoList';

export const CollaborativeEditor: WithActionProps<
  CollaborativeEditorDataProps
> = props => {
  const { initializeYjs, cleanup } = useTodoStore();

  // Extract data from props (ReactComponent hook passes data attributes as props)
  const workflowId = props['data-workflow-id'];
  const workflowName = props['data-workflow-name'];
  const userId = props['data-user-id'];
  const userName = props['data-user-name'];

  useEffect(() => {
    // Use the injected LiveView functions from ReactComponent hook
    const liveViewHook = {
      pushEvent: props.pushEvent,
      pushEventTo: props.pushEventTo,
      handleEvent: props.handleEvent,
      el: props.el,
      containerEl: props.containerEl,
      getUserInfo: () => ({
        userId,
        userName,
        workflowId,
      }),
    };

    if (userId && userName) {
      console.log('CollaborativeEditor: Initializing Yjs with LiveView hook', {
        userId,
        userName,
        workflowId,
        hasLiveViewFunctions: true,
      });
      initializeYjs(liveViewHook, userId, userName);
    } else {
      console.warn('CollaborativeEditor: Missing user info', {
        userId,
        userName,
        workflowId,
      });
    }

    // Cleanup when component unmounts
    return () => {
      cleanup();
    };
  }, [
    workflowId,
    userId,
    userName,
    initializeYjs,
    cleanup,
    props.pushEvent,
    props.handleEvent,
    props.el,
    props.containerEl,
    props.pushEventTo,
  ]);

  return (
    <div className="collaborative-editor">
      {/* Development info */}
      <div className="mb-6 p-4 bg-green-50 border border-green-200 rounded-lg">
        <h3 className="text-lg font-semibold text-green-800 mb-2">
          ✅ Phase 1 Complete - LiveView Integration Active
        </h3>
        <div className="text-sm text-green-700 space-y-1">
          <p>
            <strong>Workflow:</strong> {workflowName} ({workflowId})
          </p>
          <p>
            <strong>User:</strong> {userName} ({userId})
          </p>
          <p>
            <strong>LiveView:</strong> ✅ Connected (WithActionProps)
          </p>
          <p>
            <strong>Status:</strong> Real-time collaboration ready
          </p>
          <p>
            <strong>Next:</strong> Open multiple tabs to test collaboration
          </p>
        </div>
      </div>

      {/* Todo List Component */}
      <TodoList />
    </div>
  );
};
