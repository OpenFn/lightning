# React Store Architecture - Collaborative Editor

This document maps the store hierarchy and responsibilities for the collaborative workflow editor to help answer: **"Where should this state go?"** and **"Do we need a new store?"**

## Architecture Overview

Lightning's collaborative editor uses a **dual-source state management** pattern:
- **Collaborative stores** use Yjs CRDTs for real-time multi-user editing
- **Reference data stores** use Phoenix Channels for server-authoritative data
- All stores implement `useSyncExternalStore` + Immer for React integration

## Store Hierarchy

```
SessionStore (Infrastructure Layer)
    ├── Manages: Y.Doc, PhoenixChannelProvider, Awareness
    ├── Provides: Connection state, sync status
    │
    ├─── WorkflowStore (Collaborative Data)
    │    ├── Uses: Y.Doc CRDTs
    │    └── Manages: Jobs, Triggers, Edges, Positions
    │
    ├─── AwarenessStore (User Presence)
    │    ├── Uses: Yjs Awareness protocol
    │    └── Manages: User cursors, selections, presence
    │
    ├─── SessionContextStore (Session Context)
    │    ├── Uses: Phoenix Channel pub/sub
    │    └── Manages: User info, Project info, App config, Permissions
    │
    ├─── AdaptorStore (Reference Data)
    │    ├── Uses: Phoenix Channel pub/sub
    │    └── Manages: NPM adaptor catalog
    │
    └─── CredentialStore (Reference Data)
         ├── Uses: Phoenix Channel pub/sub
         └── Manages: Project & keychain credentials

common.ts (Shared Utilities)
    └── createWithSelector: Memoized selectors

devtools.ts (Development Utilities)
    └── Redux DevTools integration for all stores
```

## Store Catalog

### SessionStore
**File:** `stores/createSessionStore.ts`

**Responsibility:** Infrastructure layer for collaborative editing. Manages the foundational WebSocket connection, Y.Doc lifecycle, and synchronization state.

**Data Source:** Creates and manages Yjs infrastructure

**Key State:**
- `ydoc`: Yjs document instance (CRDT)
- `provider`: PhoenixChannelProvider (WebSocket)
- `awareness`: Awareness protocol instance
- `isConnected`: Connection status
- `isSynced`: Sync status
- `settled`: Both connected AND first update received
- `userData`: Local user data (id, name, color) for awareness
- `lastStatus`: Last connection status message

**When to use:**
- Need access to Y.Doc instance
- Check connection/sync status
- Initialize collaborative session
- Access Phoenix Channel provider

**Don't use for:** Domain data (jobs, credentials, etc.)

---

### WorkflowStore
**File:** `stores/createWorkflowStore.ts`

**Responsibility:** Single source of truth for collaborative workflow editing. Bridges Yjs CRDT data structures with React rendering system for real-time multi-user workflow editing.

**Data Source:** Yjs Y.Doc (collaborative)

**Key State:**
- `workflow`: Workflow metadata (id, name)
- `jobs`: Job nodes with Y.Text bodies
- `triggers`: Trigger nodes (Webhook, Cron, Kafka)
- `edges`: Connections between nodes
- `positions`: Node layout coordinates
- `selectedJobId`, `selectedTriggerId`, `selectedEdgeId`: Local selections (not synced)
- `enabled`: Computed from triggers (whether workflow is enabled)
- `selectedNode`: Computed selected job or trigger object
- `selectedEdge`: Computed selected edge object

**When to use:**
- Read/update workflow structure
- Add/remove/update jobs, triggers, edges
- Manage node positions on canvas
- Handle node selection state
- Access job body Y.Text for Monaco editor

**Don't use for:** User presence, credentials, adaptors

**Key Methods:**
- Commands: `updateJob()`, `addJob()`, `removeJob()`, `updateTrigger()`, `selectJob()`
- Queries: `getJobBodyYText()`, `saveWorkflow()`, `resetWorkflow()`

---

### AwarenessStore
**File:** `stores/createAwarenessStore.ts`

**Responsibility:** Real-time user presence and collaboration state. Manages who is online, cursor positions, and text selections.

**Data Source:** Yjs Awareness protocol

**Key State:**
- `users`: All connected users (sorted by name)
- `localUser`: Current user's data (id, name, color)
- `isInitialized`: Setup status
- `isConnected`: Connection status
- `rawAwareness`: Direct access to Yjs Awareness instance
- `lastUpdated`: Timestamp of last awareness update

**Each user contains:**
- `cursor`: { x, y } for diagram interactions
- `selection`: { anchor, head } for text selections (RelativePosition)

**When to use:**
- Render remote user cursors on workflow diagram
- Show user presence indicators
- Update local cursor/selection for Monaco editor collaboration
- Display "who's online" lists

**Don't use for:** Workflow data, credentials, adaptors

**Key Methods:**
- Commands: `updateLocalCursor()`, `updateLocalSelection()`, `updateLastSeen()`
- Queries: `getAllUsers()`, `getRemoteUsers()`, `getUserById()`

---

### SessionContextStore
**File:** `stores/createSessionContextStore.ts`

**Responsibility:** Manages session-scoped, non-collaborative context data that defines "who is editing, and what scope". Provides user information, project metadata, and app configuration for the current editing session.

**Data Source:** Phoenix Channel (server-authoritative)

**Key State:**
- `user`: Current user data (id, first_name, last_name, email, email_confirmed, inserted_at)
- `project`: Current project data (id, name)
- `config`: App configuration flags (require_email_verification, etc.)
- `permissions`: User permissions for current workflow/project
- `latestSnapshotLockVersion`: Lock version for optimistic locking on workflow saves
- `isLoading`: Request in progress
- `error`: Error state
- `lastUpdated`: Timestamp of last context update

**When to use:**
- Display user information in header (avatar initials, name)
- Build breadcrumb navigation with project links
- Check app configuration flags (email verification requirements)
- Show email verification banner
- Access session context data (who is editing what project/workflow)

**Don't use for:** Collaborative workflow data, user presence, credentials, adaptors

**Key Methods:**
- Commands: `requestSessionContext()`
- Queries: Access via `user`, `project`, `config`, `permissions` state

**Note:** This store represents the "context" of the current editing session - it's fetched once at session start and typically doesn't change during the session.

---

### AdaptorStore
**File:** `stores/createAdaptorStore.ts`

**Responsibility:** Read-only reference data for available OpenFn adaptors (NPM packages) and their versions. Used for job configuration UIs.

**Data Source:** Phoenix Channel (server-authoritative)

**Key State:**
- `adaptors`: Array of adaptors with versions
- `isLoading`: Request in progress
- `error`: Error state
- `lastUpdated`: Timestamp of last adaptor data update

**Each adaptor contains:**
- `name`: Package name (e.g., "@openfn/language-http")
- `versions`: Array of available versions
- `latest`: Latest version string
- `repo`: GitHub repository URL

**When to use:**
- Populate adaptor selection dropdowns
- Validate adaptor names/versions
- Display adaptor metadata

**Don't use for:** Job data, credentials, user presence

**Key Methods:**
- Commands: `requestAdaptors()`
- Queries: `findAdaptorByName()`, `getLatestVersion()`, `getVersions()`

---

### CredentialStore
**File:** `stores/createCredentialStore.ts`

**Responsibility:** Manages credential data lifecycle for both project-scoped and keychain (global) credentials. Provides reactive state for job configuration.

**Data Source:** Phoenix Channel (server-authoritative)

**Key State:**
- `projectCredentials`: Project-scoped credentials
- `keychainCredentials`: Global credential references
- `isLoading`: Request in progress
- `error`: Error state
- `lastUpdated`: Timestamp of last credential data update

**When to use:**
- Populate credential selection dropdowns in job forms
- Display available credentials for current project
- Access keychain credentials

**Don't use for:** Workflow data, user presence, adaptors

**Note:** Credentials are read-only from client perspective. Creation/editing happens via server forms.

**Key Methods:**
- Commands: `requestCredentials()`
- Queries: Access via `projectCredentials` and `keychainCredentials` state

---

### common.ts
**File:** `stores/common.ts`

**Responsibility:** Foundational utilities that establish core architectural patterns for all stores.

**Exports:**
1. **`createWithSelector<TState>(getSnapshot)`**
   - Creates memoized selectors with referential stability
   - Enables fine-grained subscriptions to state slices
   - Core performance optimization utility

3. **`WithSelector<TState>`** type
   - TypeScript type for selector factory functions
   - Ensures type safety across stores

**When to use:**
- Every store MUST use `createWithSelector` for performance
- Import `WithSelector` type for store type definitions

---

### devtools.ts
**File:** `stores/devtools.ts`

**Responsibility:** Redux DevTools integration for debugging and development. Provides time-travel debugging, action tracking, and state inspection for all stores in development mode.

**Key Features:**
- Wraps stores with Redux DevTools connection
- Serializes state for DevTools (excludes circular references like `ydoc`, `provider`)
- Tracks all store actions with timestamps
- Automatically disabled in production builds

**When to use:**
- Automatically integrated into all stores during development
- Open Redux DevTools browser extension to inspect store state
- Use time-travel debugging to replay actions
- Export/import state for bug reproduction

**Don't use directly:** This utility is used internally by store implementations via `wrapStoreWithDevTools()`.

---

## Decision Tree: "Where Should This State Go?"

### 1. Is it collaborative workflow data?
**YES** → Use **WorkflowStore**
- Jobs, triggers, edges, workflow metadata
- Node positions on canvas
- Anything that needs to sync between users in real-time

### 2. Is it user presence/collaboration metadata?
**YES** → Use **AwarenessStore**
- Cursor positions
- Text selections
- User online status
- "Who's editing what" indicators

### 3. Is it connection/infrastructure state?
**YES** → Use **SessionStore**
- Connection status
- Sync status
- Y.Doc lifecycle
- Phoenix Channel management

### 4. Is it session-scoped context data?
**YES** → Use **SessionContextStore**
- Current user information
- Current project information
- App configuration flags
- Session initialization data that rarely changes

### 5. Is it server-managed reference data?
**YES** → Determine type:
- **NPM adaptors?** → Use **AdaptorStore**
- **Credentials?** → Use **CredentialStore**
- **Session context?** → Use **SessionContextStore**
- **Something else?** → Consider creating new Phoenix Channel-based store (see below)

### 6. Is it local component UI state?
**YES** → Use component-local state (useState/useReducer)
- Modal open/closed
- Form validation errors
- Temporary UI flags
- Anything that doesn't need to persist or sync

### 7. Is it URL-synced state?
**YES** → Use WorkflowStore + URL sync hooks
- Selected node IDs (see `useNodeSelection` in `hooks/useWorkflow.ts`)
- Current view/panel state
- Navigation state

---

## Store Update Patterns

All stores implement one or more of these patterns:

### Pattern 1: Y.Doc/Awareness → Observer → Immer → Notify
**Used for:** Collaborative data from Yjs
**Stores:** WorkflowStore, AwarenessStore
**Flow:**
```
User edits → Y.Doc transaction → Observer fires → Immer update → React re-render
```

### Pattern 2: Direct Immer → Notify + Y.Doc/Awareness Update
**Used for:** Local commands that need immediate UI feedback + sync
**Stores:** WorkflowStore (selections), AwarenessStore (local cursor)
**Flow:**
```
Command → Update Y.Doc → Immediate Immer update → notify → React re-render
(Y.Doc observer also fires but state already updated = idempotent)
```

### Pattern 3: Phoenix Channel → Zod Validation → Immer → Notify
**Used for:** Server-authoritative reference data
**Stores:** AdaptorStore, CredentialStore
**Flow:**
```
Server broadcast → Zod validation → Immer update → React re-render
```

---

## When to Create a New Store

### Create a NEW store when:

1. **New domain of data** with independent lifecycle
   - Example: Adding "project templates" → Create `TemplateStore`
   - Example: Adding "notification preferences" → Create `PreferenceStore`

2. **Different data source pattern**
   - New Yjs Map/Array in Y.Doc → New collaborative store
   - New Phoenix Channel event stream → New reference data store

3. **Clear separation of concerns**
   - Store would have 5+ unrelated responsibilities → Split into multiple stores
   - Mixing collaborative and reference data → Separate stores

4. **Performance isolation**
   - High-frequency updates affecting unrelated UI → Separate store
   - Large datasets that don't need to trigger other re-renders → Separate store

### DON'T create a new store when:

1. **Data is closely related to existing store**
   - Adding new workflow fields → Add to WorkflowStore
   - Adding new user presence data → Add to AwarenessStore

2. **It's component-local UI state**
   - Use `useState` or `useReducer` instead

3. **It's derived/computed state**
   - Use selectors with existing stores
   - Example: `useWorkflowSelector(state => state.jobs.filter(...))`

4. **It's temporary/session data**
   - Use SessionStorage or in-memory caching instead

---

## Store Creation Checklist

If you've decided to create a new store, follow this pattern:

```typescript
// 1. Define types
interface MyState { /* ... */ }
interface MyStore { subscribe, getSnapshot, withSelector, /* commands */, /* queries */ }

// 2. Create factory function
export const createMyStore = () => {
  // Initialize Immer state
  let state: MyState = produce({ /* initial */ }, draft => draft);

  // Listener management
  const listeners = new Set<() => void>();
  const notify = () => listeners.forEach(l => l());
  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  };

  // Store interface
  const getSnapshot = () => state;
  const withSelector = createWithSelector(getSnapshot);

  // Commands (mutations) - use produce()
  const updateSomething = (data) => {
    state = produce(state, draft => {
      draft.something = data;
    });
    notify();
  };

  // Queries (reads) - pure functions
  const getSomething = () => state.something;

  return {
    subscribe,
    getSnapshot,
    withSelector,
    updateSomething,
    getSomething,
  };
};
```

3. Add to StoreProvider context
4. Create hooks in `hooks/useMyStore.ts`
5. Follow Command Query Separation (CQS)
6. Use appropriate update pattern (see above)

---

## Key Architectural Principles

1. **Command Query Separation**: Separate mutations (commands) from reads (queries)
2. **Referential Stability**: Use Immer + `createWithSelector` for optimal React performance
3. **Single Responsibility**: Each store manages one domain of data
4. **Type Safety**: Zod for runtime validation, TypeScript for compile-time safety
5. **useSyncExternalStore**: All stores implement React 18's external store pattern
6. **Immutability**: All state updates via Immer's `produce()`

---

## Common Anti-Patterns to Avoid

❌ **Mixing collaborative and reference data in one store**
- Split into separate stores based on data source

❌ **Creating store for component-local state**
- Use `useState` instead

❌ **Not using `createWithSelector`**
- Results in unnecessary re-renders

❌ **Updating state without `produce()`**
- Breaks referential stability guarantees

❌ **Commands that don't notify**
- React won't re-render

❌ **Queries with side effects**
- Violates CQS principle

---

## Related Files

- **Store Implementations**: `assets/js/collaborative-editor/stores/`
  - `createSessionStore.ts` - Infrastructure layer
  - `createWorkflowStore.ts` - Collaborative workflow data
  - `createAwarenessStore.ts` - User presence
  - `createSessionContextStore.ts` - Session context
  - `createAdaptorStore.ts` - Adaptor reference data
  - `createCredentialStore.ts` - Credential reference data
  - `common.ts` - Shared utilities
  - `devtools.ts` - Redux DevTools integration
- **Store Hooks**: `assets/js/collaborative-editor/hooks/`
- **Store Context**: `assets/js/collaborative-editor/contexts/StoreProvider.tsx`
- **Type Definitions**: `assets/js/collaborative-editor/types/`

---

**Last Updated:** 2025-10-08 (Fixed incorrect state properties, added devtools.ts, updated method names)
**Maintainer:** Lightning Core Team
