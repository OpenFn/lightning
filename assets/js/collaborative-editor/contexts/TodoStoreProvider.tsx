/**
 * TodoStoreProvider - Yjs TodoStore that uses WorkflowChannel for transport
 * Uses YjsChannelProvider for clean separation of concerns
 */

import React, { createContext, useContext, useEffect, useState } from 'react';
import * as Y from 'yjs';
import * as awarenessProtocol from 'y-protocols/awareness';
import { useSocket } from '../../react/contexts/SocketProvider';
import { PhoenixChannelProvider } from 'y-phoenix-channel';
import type { TodoItem, AwarenessUser, TodoStore } from '../types/todo';

interface TodoStoreContextValue extends TodoStore {
  ydoc: Y.Doc | null;
  awareness: awarenessProtocol.Awareness | null;
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
  workflowId: string;
  userId: string;
  userName: string;
  children: React.ReactNode;
}

export const TodoStoreProvider: React.FC<TodoStoreProviderProps> = ({
  workflowId,
  userId,
  userName,
  children,
}) => {
  const { socket, isConnected } = useSocket();

  // Yjs state
  const [ydoc, setYdoc] = useState<Y.Doc | null>(null);
  const [awareness, setAwareness] =
    useState<awarenessProtocol.Awareness | null>(null);
  const [provider, setProvider] = useState<PhoenixChannelProvider | null>(null);
  const [todoItems, setTodoItems] = useState<Y.Map<TodoItem> | null>(null);
  const [todoOrder, setTodoOrder] = useState<Y.Array<string> | null>(null);

  // React state
  const [todos, setTodos] = useState<TodoItem[]>([]);
  const [users, setUsers] = useState<AwarenessUser[]>([]);
  const [isProviderConnected, setIsProviderConnected] = useState(false);
  const [isSynced, setIsSynced] = useState(false);

  // Initialize Yjs when socket is connected
  useEffect(() => {
    if (!isConnected || !socket) {
      return;
    }

    console.log('🚀 Initializing Yjs with PhoenixChannelProvider');

    // Create Yjs document and awareness
    const doc = new Y.Doc();
    const awarenessInstance = new awarenessProtocol.Awareness(doc);
    const items = doc.getMap<TodoItem>('todoItems');
    const order = doc.getArray<string>('todoOrder');

    // Set up awareness with user info
    const userData = {
      id: userId,
      name: userName,
      color: generateUserColor(userId),
    };

    awarenessInstance.setLocalStateField('user', userData);

    // Create the Yjs channel provider with the reference implementation
    const roomname = `workflow:collaborate:${workflowId}`;
    console.log('🔗 Creating PhoenixChannelProvider with:', {
      roomname,
      socketConnected: socket.isConnected(),
    });

    const channelProvider = new PhoenixChannelProvider(socket, roomname, doc, {
      awareness: awarenessInstance,
      connect: true,
    });

    console.log('🔗 PhoenixChannelProvider created:', channelProvider);

    // Listen to React state sync
    const syncTodos = () => {
      const todoMap = items.toJSON() as Record<string, TodoItem>;
      const orderArray = order.toArray();
      const orderedTodos = orderArray
        .map(id => todoMap[id])
        .filter(todo => todo !== undefined);
      setTodos(orderedTodos);
    };

    const syncUsers = () => {
      const userList: AwarenessUser[] = [];
      awarenessInstance.getStates().forEach((state, clientId) => {
        if (state['user']) {
          userList.push({
            clientId,
            user: state['user'],
            cursor: state['cursor'],
          });
        }
      });
      setUsers(userList);
    };

    // Set up observers
    items.observe(syncTodos);
    order.observe(syncTodos);
    awarenessInstance.on('change', syncUsers);

    // Try different approaches to event listening
    const statusHandler = (...args: any[]) => {
      console.log('📡 PhoenixChannelProvider status event (all args):', args);
      if (args.length > 0 && Array.isArray(args[0])) {
        const statusEvents = args[0];
        if (
          statusEvents[0] &&
          typeof statusEvents[0] === 'object' &&
          'status' in statusEvents[0]
        ) {
          const status = (statusEvents[0] as { status: string }).status;
          console.log(
            '📡 Setting provider connected to:',
            status === 'connected'
          );
          setIsProviderConnected(status === 'connected');
        }
      }
    };

    const syncHandler = (...args: any[]) => {
      console.log('🔄 PhoenixChannelProvider synced event (all args):', args);
      if (args.length > 0 && Array.isArray(args[0])) {
        setIsSynced(args[0][0] === true);
      }
    };

    // Listen to provider status (reference implementation uses different event structure)
    (channelProvider as any).on('status', statusHandler);
    (channelProvider as any).on('synced', syncHandler);

    // Also listen to sync events (might be different)
    (channelProvider as any).on('sync', syncHandler);

    // Also log initial provider state
    console.log('🚀 PhoenixChannelProvider initial state:', {
      roomname,
      shouldConnect: channelProvider.shouldConnect,
      channel: channelProvider.channel,
      synced: channelProvider.synced,
      socketConnected: socket.isConnected(),
    });

    // Check the provider's current connection status periodically
    const statusCheckInterval = setInterval(() => {
      const currentStatus = {
        channel: channelProvider.channel?.state,
        synced: channelProvider.synced,
        socketConnected: socket.isConnected(),
      };
      console.log('🔍 Provider status check:', currentStatus);

      // Manually update connection status based on channel state
      if (channelProvider.channel?.state === 'joined') {
        setIsProviderConnected(true);
      } else {
        setIsProviderConnected(false);
      }

      // Update sync status
      setIsSynced(channelProvider.synced);
    }, 2000); // Check every 2 seconds

    // Store state
    setYdoc(doc);
    setAwareness(awarenessInstance);
    setProvider(channelProvider);
    setTodoItems(items);
    setTodoOrder(order);

    // Provider auto-connects if connect: true is passed

    // Initial sync
    syncTodos();
    syncUsers();

    // Cleanup function
    return () => {
      console.log('🧹 Cleaning up Yjs document');
      clearInterval(statusCheckInterval);
      channelProvider.destroy();
      doc.destroy();
      setYdoc(null);
      setAwareness(null);
      setProvider(null);
      setTodoItems(null);
      setTodoOrder(null);
      setTodos([]);
      setUsers([]);
      setIsProviderConnected(false);
      setIsSynced(false);
    };
  }, [isConnected, socket, workflowId, userId, userName]);

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
    ydoc,
    awareness,
    todos,
    users,
    isConnected: isProviderConnected,
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

  return colors[Math.abs(hash) % colors.length] || '#999999';
}
