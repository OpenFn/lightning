/**
 * TypeScript interfaces for the collaborative todo system
 */

export interface TodoItem {
  id: string;
  text: string;
  completed: boolean;
  createdAt: number;
  updatedAt: number;
  createdBy: string; // user_id
}

export interface AwarenessUser {
  clientId: number;
  user: {
    id: string;
    name: string;
    color: string;
  };
  cursor?: {
    x: number;
    y: number;
  };
}

export interface TodoStore {
  todos: TodoItem[];
  addTodo: (text: string) => void;
  toggleTodo: (id: string) => void;
  deleteTodo: (id: string) => void;
  updateTodoText: (id: string, text: string) => void;
  reorderTodos: (startIndex: number, endIndex: number) => void;
  users: AwarenessUser[];
  isConnected: boolean;
  isSynced: boolean;
}

export interface YjsCollaborativeHookEvents {
  'yjs_update': (message: any) => void;
  'yjs_awareness': (message: any) => void;
  'sync_request': (message: any) => void;
  'yjs_response': (message: any) => void;
  'yjs_query_awareness': (message: any) => void;
}

// Data attributes passed from LiveView template to React component
export interface CollaborativeEditorDataProps {
  'data-workflow-id': string;
  'data-workflow-name': string;
  'data-user-id': string;
  'data-user-name': string;
}