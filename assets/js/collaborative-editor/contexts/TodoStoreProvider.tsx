/**
 * TodoStoreProvider - Yjs TodoStore for todo-specific operations
 * Uses SessionProvider for shared Yjs/Phoenix Channel infrastructure
 */

import React, { createContext, useContext, useEffect, useState } from 'react';
import * as Y from 'yjs';
import type { TodoItem, TodoStore } from '../types/todo';
import { useSession } from './SessionProvider';

interface TodoStoreContextValue extends TodoStore {
  // Domain-specific todo operations only
  // Session concerns (ydoc, awareness, users, connection) come from useSession
}

const TodoStoreContext = createContext<TodoStoreContextValue | null>(null);

export const useTodoStore = () => {
  const context = useContext(TodoStoreContext);
  if (!context) {
    throw new Error('useTodoStore must be used within a TodoStoreProvider');
  }
  return context;
};

interface TodoStoreProviderProps {
  children: React.ReactNode;
}

export const TodoStoreProvider: React.FC<TodoStoreProviderProps> = ({
  children,
}) => {
  const { ydoc, isConnected, isSynced, users } = useSession();

  // Domain-specific Yjs state
  const [todoItems, setTodoItems] = useState<Y.Map<TodoItem> | null>(null);
  const [todoOrder, setTodoOrder] = useState<Y.Array<string> | null>(null);

  // Domain-specific React state
  const [todos, setTodos] = useState<TodoItem[]>([]);
  const [userId, setUserId] = useState<string>('');

  // Get userId from session users (current user)
  useEffect(() => {
    if (users.length > 0) {
      // Find the current user (the local user)
      const currentUser = users.find(u => u.user.id);
      if (currentUser) {
        setUserId(currentUser.user.id);
      }
    }
  }, [users]);

  // Initialize domain-specific Yjs maps when ydoc is available
  useEffect(() => {
    if (!ydoc) {
      return;
    }

    console.log('🚀 Initializing TodoStore domain maps');

    // Get domain-specific Yjs maps
    const items = ydoc.getMap<TodoItem>('todoItems');
    const order = ydoc.getArray<string>('todoOrder');

    // Sync todos to React state
    const syncTodos = () => {
      const todoMap = items.toJSON() as Record<string, TodoItem>;
      const orderArray = order.toArray();
      const orderedTodos = orderArray
        .map(id => todoMap[id])
        .filter(todo => todo !== undefined);
      setTodos(orderedTodos);
    };

    // Set up observers for domain-specific data
    items.observe(syncTodos);
    order.observe(syncTodos);

    // Store domain state
    setTodoItems(items);
    setTodoOrder(order);

    // Initial sync
    syncTodos();

    // Cleanup function
    return () => {
      console.debug('TodoStore: cleaning up domain maps');
      setTodoItems(null);
      setTodoOrder(null);
      setTodos([]);
    };
  }, [ydoc]);

  // Todo operations
  const addTodo = (text: string) => {
    if (!todoItems || !todoOrder) return;

    const id = generateTodoId();
    const todo: TodoItem = {
      id,
      text,
      completed: false,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      createdBy: userId,
    };

    todoItems.set(id, todo);
    todoOrder.push([id]);
  };

  const toggleTodo = (id: string) => {
    if (!todoItems) return;

    const todo = todoItems.get(id);
    if (todo) {
      todoItems.set(id, {
        ...todo,
        completed: !todo.completed,
        updatedAt: Date.now(),
      });
    }
  };

  const deleteTodo = (id: string) => {
    if (!todoItems || !todoOrder) return;

    todoItems.delete(id);

    // Remove from order array
    const index = todoOrder.toArray().indexOf(id);
    if (index !== -1) {
      todoOrder.delete(index, 1);
    }
  };

  const updateTodoText = (id: string, text: string) => {
    if (!todoItems) return;

    const todo = todoItems.get(id);
    if (todo && text.trim()) {
      todoItems.set(id, {
        ...todo,
        text: text.trim(),
        updatedAt: Date.now(),
      });
    }
  };

  const reorderTodos = (startIndex: number, endIndex: number) => {
    if (!todoOrder) return;

    const items = todoOrder.toArray();
    const removed = items.splice(startIndex, 1)[0];
    if (removed) {
      items.splice(endIndex, 0, removed);
    }

    // Clear and rebuild the array
    todoOrder.delete(0, todoOrder.length);
    todoOrder.insert(0, items);
  };

  const value: TodoStoreContextValue = {
    todos,
    users,
    isConnected,
    isSynced,
    addTodo,
    toggleTodo,
    deleteTodo,
    updateTodoText,
    reorderTodos,
  };

  return (
    <TodoStoreContext.Provider value={value}>
      {children}
    </TodoStoreContext.Provider>
  );
};

// Helper functions
function generateTodoId(): string {
  return `todo_${Date.now()}_${Math.random().toString(36).substring(2, 11)}`;
}
