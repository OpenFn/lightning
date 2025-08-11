import type React from "react";
import { useState } from "react";
import { useTodoStore } from "../contexts/TodoStoreProvider";
import type { TodoItem as TodoItemType } from "../types/todo";

interface TodoItemProps {
  todo: TodoItemType;
  index: number;
}

export const TodoItem: React.FC<TodoItemProps> = ({ todo }) => {
  const [isEditing, setIsEditing] = useState(false);
  const [editText, setEditText] = useState(todo.text);
  const { toggleTodo, deleteTodo, updateTodoText, users } = useTodoStore();

  const handleEdit = () => {
    setIsEditing(true);
    setEditText(todo.text);
  };

  const handleSave = () => {
    if (editText.trim() && editText !== todo.text) {
      updateTodoText(todo.id, editText.trim());
    }
    setIsEditing(false);
  };

  const handleCancel = () => {
    setEditText(todo.text);
    setIsEditing(false);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter") {
      handleSave();
    } else if (e.key === "Escape") {
      handleCancel();
    }
  };

  // Find the creator user info
  const creator = users.find((user) => user.user.id === todo.createdBy);
  const creatorColor = creator?.user.color || "#gray";

  return (
    <div
      className="flex items-center gap-3 p-3 bg-white border rounded-lg 
                    shadow-sm hover:shadow-md transition-shadow group"
    >
      {/* Checkbox */}
      <input
        type="checkbox"
        checked={todo.completed}
        onChange={() => toggleTodo(todo.id)}
        className="w-5 h-5 text-blue-600 rounded focus:ring-blue-500"
      />

      {/* Todo content */}
      <div className="flex-1 min-w-0">
        {isEditing ? (
          <input
            type="text"
            value={editText}
            onChange={(e) => setEditText(e.target.value)}
            onBlur={handleSave}
            onKeyDown={handleKeyDown}
            className="w-full px-2 py-1 border rounded text-gray-900 
                       focus:outline-none focus:ring-1 focus:ring-blue-500"
            autoFocus
          />
        ) : (
          <span
            className={`block text-gray-900 cursor-pointer ${
              todo.completed ? "line-through text-gray-500" : ""
            }`}
            onClick={handleEdit}
          >
            {todo.text}
          </span>
        )}

        {/* Metadata */}
        <div className="flex items-center gap-2 mt-1 text-xs text-gray-500">
          <span
            className="inline-block w-2 h-2 rounded-full"
            style={{ backgroundColor: creatorColor }}
            title={`Created by ${creator?.user.name || "Unknown"}`}
          />
          <span>{new Date(todo.createdAt).toLocaleTimeString()}</span>
          {todo.updatedAt !== todo.createdAt && (
            <span className="text-gray-400">
              (edited {new Date(todo.updatedAt).toLocaleTimeString()})
            </span>
          )}
        </div>
      </div>

      {/* Actions */}
      <div
        className="flex gap-1 opacity-0 group-hover:opacity-100 
                      transition-opacity"
      >
        {!isEditing && (
          <>
            <button
              onClick={handleEdit}
              className="p-1 text-gray-400 hover:text-blue-500 
                         transition-colors"
              title="Edit todo"
            >
              <svg
                className="w-4 h-4"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
                />
              </svg>
            </button>
            <button
              onClick={() => deleteTodo(todo.id)}
              className="p-1 text-gray-400 hover:text-red-500 
                         transition-colors"
              title="Delete todo"
            >
              <svg
                className="w-4 h-4"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                />
              </svg>
            </button>
          </>
        )}
      </div>
    </div>
  );
};
