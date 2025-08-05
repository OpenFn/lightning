/**
 * Zustand store for collaborative todo list
 * Bridges between Yjs CRDT and React components
 */

import { create } from 'zustand';
import * as Y from 'yjs';
import * as awarenessProtocol from 'y-protocols/awareness';
import type { TodoItem, AwarenessUser, TodoStore } from '../types/todo';
import { YjsPhoenixProvider } from '../lib/yjs-phoenix-provider';

interface TodoStoreState extends TodoStore {
  // Internal state
  ydoc?: Y.Doc;
  provider?: YjsPhoenixProvider;
  todoItems?: Y.Map<TodoItem>;
  todoOrder?: Y.Array<string>;

  // Setup functions
  initializeYjs: (hook: any, userId: string, userName: string) => void;
  cleanup: () => void;
}

export const useTodoStore = create<TodoStoreState>((set, get) => ({
  // State
  todos: [],
  users: [],
  isConnected: false,
  isSynced: false,

  // Setup functions
  initializeYjs: (hook: any, userId: string, userName: string) => {
    console.log(
      'DEBUG: Initializing Yjs with userId:',
      userId,
      'userName:',
      userName
    );
    const ydoc = new Y.Doc();
    const todoItems = ydoc.getMap<TodoItem>('todoItems');
    const todoOrder = ydoc.getArray<string>('todoOrder');
    const awareness = new awarenessProtocol.Awareness(ydoc);

    // Set up awareness with user info
    awareness.setLocalStateField('user', {
      id: userId,
      name: userName,
      color: generateUserColor(userId),
    });

    const provider = new YjsPhoenixProvider(ydoc, hook, { awareness });

    // Listen to document changes
    todoItems.observe(() => {
      syncTodosFromYjs(todoItems, todoOrder, set);
    });

    todoOrder.observe(() => {
      syncTodosFromYjs(todoItems, todoOrder, set);
    });

    // Listen to awareness changes
    awareness.on('change', () => {
      syncUsersFromAwareness(awareness, set);
    });

    // Listen to provider status
    provider.on('status', ({ status }: { status: string }) => {
      set({ isConnected: status === 'connected' });
    });

    provider.on('synced', (synced: boolean) => {
      set({ isSynced: synced });
    });

    // Store references
    set({
      ydoc,
      provider,
      todoItems,
      todoOrder,
      isConnected: true,
    });

    // Connect to server
    provider.connect();
  },

  cleanup: () => {
    const { provider, ydoc } = get();
    if (provider) {
      provider.destroy();
    }
    if (ydoc) {
      ydoc.destroy();
    }
    set({
      ydoc: undefined,
      provider: undefined,
      todoItems: undefined,
      todoOrder: undefined,
      todos: [],
      users: [],
      isConnected: false,
      isSynced: false,
    });
  },

  // Todo operations
  addTodo: (text: string) => {
    const { todoItems, todoOrder } = get();
    if (!todoItems || !todoOrder) return;

    const id = generateTodoId();
    const todo: TodoItem = {
      id,
      text,
      completed: false,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      createdBy: getCurrentUserId(),
    };

    todoItems.set(id, todo);
    todoOrder.push([id]);
  },

  toggleTodo: (id: string) => {
    const { todoItems } = get();
    if (!todoItems) return;

    const todo = todoItems.get(id);
    if (todo) {
      todoItems.set(id, {
        ...todo,
        completed: !todo.completed,
        updatedAt: Date.now(),
      });
    }
  },

  deleteTodo: (id: string) => {
    const { todoItems, todoOrder } = get();
    if (!todoItems || !todoOrder) return;

    todoItems.delete(id);

    // Remove from order array
    const index = todoOrder.toArray().indexOf(id);
    if (index !== -1) {
      todoOrder.delete(index, 1);
    }
  },

  updateTodoText: (id: string, text: string) => {
    const { todoItems } = get();
    if (!todoItems) return;

    const todo = todoItems.get(id);
    if (todo) {
      todoItems.set(id, {
        ...todo,
        text,
        updatedAt: Date.now(),
      });
    }
  },

  reorderTodos: (startIndex: number, endIndex: number) => {
    const { todoOrder } = get();
    if (!todoOrder) return;

    const items = todoOrder.toArray();
    const [removed] = items.splice(startIndex, 1);
    items.splice(endIndex, 0, removed);

    // Clear and rebuild the array
    todoOrder.delete(0, todoOrder.length);
    todoOrder.insert(0, items);
  },
}));

// Helper functions
function syncTodosFromYjs(
  todoItems: Y.Map<TodoItem>,
  todoOrder: Y.Array<string>,
  set: (state: Partial<TodoStoreState>) => void
) {
  const todoMap = todoItems.toJSON() as Record<string, TodoItem>;
  const order = todoOrder.toArray();

  // Create ordered todos array
  const todos = order.map(id => todoMap[id]).filter(todo => todo !== undefined);

  set({ todos });
}

function syncUsersFromAwareness(
  awareness: awarenessProtocol.Awareness,
  set: (state: Partial<TodoStoreState>) => void
) {
  const users: AwarenessUser[] = [];

  awareness.getStates().forEach((state, clientId) => {
    if (state.user) {
      users.push({
        clientId,
        user: state.user,
        cursor: state.cursor,
      });
    }
  });

  set({ users });
}

function generateTodoId(): string {
  return `todo_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

function generateUserColor(userId: string): string {
  const colors = [
    '#FF6B6B',
    '#4ECDC4',
    '#45B7D1',
    '#FFA07A',
    '#98D8C8',
    '#FFCF56',
    '#FF8B94',
    '#AED581',
  ];

  const hash = userId.split('').reduce((a, b) => {
    a = (a << 5) - a + b.charCodeAt(0);
    return a & a;
  }, 0);

  return colors[Math.abs(hash) % colors.length];
}

function getCurrentUserId(): string {
  // This will be set by the provider initialization
  const element = document.querySelector('[data-user-id]') as HTMLElement;
  return element?.dataset?.userId || 'anonymous';
}
