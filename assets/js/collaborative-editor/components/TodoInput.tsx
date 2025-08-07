import React, { useState } from 'react';
import { useTodoStore } from '../contexts/TodoStoreProvider';

export const TodoInput: React.FC = () => {
  const [text, setText] = useState('');
  const { addTodo, isConnected } = useTodoStore();

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (text.trim()) {
      addTodo(text.trim());
      setText('');
    }
  };

  return (
    <form onSubmit={handleSubmit} className="mb-4">
      <div className="flex gap-2">
        <input
          type="text"
          value={text}
          onChange={e => setText(e.target.value)}
          placeholder="Add a new todo..."
          className="flex-1 px-3 py-2 border border-gray-300 rounded-md 
                     focus:outline-none focus:ring-2 focus:ring-blue-500 
                     disabled:bg-gray-100"
          disabled={!isConnected}
        />
        <button
          type="submit"
          disabled={!text.trim() || !isConnected}
          className="px-4 py-2 bg-blue-500 text-white rounded-md 
                     hover:bg-blue-600 disabled:bg-gray-300 
                     disabled:cursor-not-allowed transition-colors"
        >
          Add
        </button>
      </div>
      {!isConnected && (
        <p className="text-sm text-red-500 mt-1">
          Disconnected - Changes will sync when reconnected
        </p>
      )}
    </form>
  );
};
