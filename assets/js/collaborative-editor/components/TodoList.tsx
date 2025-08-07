import React from 'react';
import { useTodoStore } from '../contexts/TodoStoreProvider';
import { TodoInput } from './TodoInput';
import { TodoItem } from './TodoItem';
import { UserAwareness } from './UserAwareness';

export const TodoList: React.FC = () => {
  const { todos } = useTodoStore();

  const completedCount = todos.filter(todo => todo.completed).length;
  const totalCount = todos.length;

  return (
    <div className="w-full max-w-2xl mx-auto p-4">
      {/* Header */}
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900 mb-2">
          Collaborative Todo List
        </h2>
        <p className="text-gray-600">
          Real-time collaboration powered by Yjs and Phoenix LiveView
        </p>
      </div>

      {/* User awareness */}
      <UserAwareness />

      {/* Add todo input */}
      <TodoInput />

      {/* Progress indicator */}
      {totalCount > 0 && (
        <div className="mb-4 p-3 bg-blue-50 border border-blue-200 rounded-lg">
          <div className="flex items-center justify-between text-sm">
            <span className="text-blue-700">
              Progress: {completedCount} of {totalCount} completed
            </span>
            <span className="text-blue-600 font-medium">
              {totalCount > 0
                ? Math.round((completedCount / totalCount) * 100)
                : 0}
              %
            </span>
          </div>
          <div className="mt-2 w-full bg-blue-200 rounded-full h-2">
            <div
              className="bg-blue-500 h-2 rounded-full transition-all duration-300"
              style={{
                width: `${
                  totalCount > 0 ? (completedCount / totalCount) * 100 : 0
                }%`,
              }}
            />
          </div>
        </div>
      )}

      {/* Todo list */}
      <div className="space-y-2">
        {todos.length === 0 ? (
          <div className="text-center py-8 text-gray-500">
            <svg
              className="w-12 h-12 mx-auto mb-3 text-gray-300"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01"
              />
            </svg>
            <p>No todos yet. Add one above to get started!</p>
          </div>
        ) : (
          todos.map((todo, index) => (
            <TodoItem key={todo.id} todo={todo} index={index} />
          ))
        )}
      </div>

      {/* Statistics */}
      {totalCount > 0 && (
        <div className="mt-6 pt-4 border-t border-gray-200">
          <div className="flex justify-between text-sm text-gray-500">
            <span>{totalCount - completedCount} remaining</span>
            <span>{completedCount} completed</span>
          </div>
        </div>
      )}
    </div>
  );
};
