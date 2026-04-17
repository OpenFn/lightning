# React Store Architecture - Collaborative Editor

This document maps the store responsibilities for the collaborative workflow editor to help answer: **"Where should this state go?"** and **"Do we need a new store?"**

## Architecture Overview

Lightning's collaborative editor uses **three layers of state management**, distinguished by their data source:

1. **Y.Doc-backed (collaborative)** — Real-time multi-user data via Yjs CRDTs
   - WorkflowStore (workflow structure), AwarenessStore (user presence)
2. **Phoenix Channel-backed (server-authoritative)** — Data pushed/pulled via the workflow channel
   - SessionContextStore, AdaptorStore, CredentialStore, HistoryStore, AIAssistantStore
3. **Local-only (no network)** — Client-side UI state
   - UIStore, EditorPreferencesStore

All stores share the same foundation: closure-based factory (`createXxxStore()`), Immer-managed state, `subscribe`/`getSnapshot` for `useSyncExternalStore`, `createWithSelector` for memoized selectors, and Redux DevTools integration in development.

## Initialization Order

All 10 stores are created as peers in `StoreProvider.tsx`'s `useState` initializer. Three `useEffect` hooks wire them to the network in dependency order:

```
1. SessionStore.initializeSession(socket, room, userData)
      │
      ├─ when isConnected ──→ _connectChannel() on:
      │     SessionContextStore, AdaptorStore, CredentialStore,
      │     HistoryStore, AIAssistantStore
      │
      ├─ when isSynced ────→ WorkflowStore.connect(ydoc, provider)
      │     (must wait for full Y.Doc sync before attaching observers)
      │
      └─ when awareness + user data ──→ AwarenessStore.initializeAwareness()
```

UIStore and EditorPreferencesStore have no network dependencies and are ready immediately.

---

## Store Catalog

### SessionStore
**File:** `stores/createSessionStore.ts`

**Intent:** Establish and maintain the collaborative session infrastructure so other stores can consume Y.Doc and Channel capabilities. This is pure plumbing — it knows HOW to connect but nothing about WHAT gets synced.

**Key State:** `ydoc`, `provider`, `awareness`, `isConnected`, `isSynced`, `settled`, `userData`, `lastStatus`

**Key behavior:**
- `settled` means both synced AND first remote update received — the signal that Y.Doc content is ready to read
- Reuses existing Y.Doc on reconnection to preserve offline edits buffered in Y.js transactions
- `createSettlingSubscription()` uses AbortController + Promise.all to track the connected→synced→settled lifecycle

**Don't use for:** Domain data (jobs, credentials, etc.) — this store has no opinion about what's in the Y.Doc.

---

### WorkflowStore
**File:** `stores/createWorkflowStore.ts`

**Intent:** Be the single source of truth for the workflow's structure and content, enabling real-time multi-user editing. This is the largest and most complex store — it IS the collaborative document model.

**Key State:** `workflow` (metadata), `jobs`, `triggers`, `edges`, `positions`, `undoManager`, `selectedJobId`/`selectedTriggerId`/`selectedEdgeId` (local), `enabled` (derived), `selectedNode`/`selectedEdge` (derived), `activeTriggerAuthMethods`, `isApplyingWorkflow`/`isApplyingJobCode` (AI coordination)

**Key behavior:**
- `connect(ydoc, provider)` obtains six Y.js structures (`workflow`, `jobs`, `triggers`, `edges`, `positions`, `errors` maps/arrays) and attaches `observeDeep` handlers
- Creates a `Y.UndoManager` with 500ms capture timeout tracking all five non-errors structures
- Validation errors are managed via `setClientErrors` (500ms debounced, merges client vs. server errors) and `mergeWithPreservedErrors` in observers
- `disconnect()` removes only channel observers, preserving Y.Doc observers and UndoManager for offline editing
- Selection state (`selectJob`, `selectTrigger`, `selectEdge`) is local-only (not synced via Y.Doc)
- AI apply coordination broadcasts (`startApplyingWorkflow`/`doneApplyingWorkflow`) let collaborators see when AI is modifying the workflow

**Commands:** `updateJob`, `addJob`, `removeJob`, `updateTrigger`, `addEdge`, `updateEdge`, `removeEdge`, `updatePositions`, `saveWorkflow`, `saveAndSyncWorkflow`, `resetWorkflow`, `importWorkflow`, `setClientErrors`, `undo`, `redo`

**Don't use for:** User presence, credentials, adaptors, UI panel state.

---

### AwarenessStore
**File:** `stores/createAwarenessStore.ts`

**Intent:** Show which users are present and what they're focused on, with graceful handling of transient disconnections. Answers "who's here?" and "what are they looking at?"

**Key State:** `users` (sorted, includes cached), `localUser`, `cursorsMap` (primary keyed by Y.js clientId), `userCache` (1-min TTL Map), `isInitialized`, `isConnected`, `rawAwareness`

**Key behavior:**
- `handleAwarenessChange` does field-by-field equality checks (including position/selection deep compare) to minimize Immer mutations
- **User cache**: recently-disconnected users stay visible for 60 seconds before fading out, preventing flicker on transient disconnections
- **lastSeen timer**: broadcasts `lastSeen` every 10 seconds; handles page visibility API (webkit/moz/ms prefixed) to freeze timestamps when the tab is hidden while keeping awareness alive
- `users` array merges live users from `cursorsMap` with non-expired cache entries, sorted by name

**Commands:** `updateLocalCursor`, `updateLocalSelection`, `updateLastSeen`, `updateLocalUserData`, `setConnected`
**Queries:** `getAllUsers`, `getRemoteUsers`, `getUserById`, `getUserByClientId`

**Don't use for:** Workflow data, credentials, adaptors.

---

### SessionContextStore
**File:** `stores/createSessionContextStore.ts`

**Intent:** Provide the server's view of "who is editing, what project, and with what permissions." This is the authorization and metadata backbone — it shapes what the UI shows and allows.

**Key State:** `user`, `project`, `config`, `permissions`, `latestSnapshotLockVersion`, `projectRepoConnection`, `webhookAuthMethods`, `versions`/`versionsLoading`/`versionsError`, `workflow_template`, `hasReadAIDisclaimer`, `limits` (runs/workflow_activation/github_sync), `isNewWorkflow`, `workflow` (base workflow metadata)

**Key behavior:**
- `requestSessionContext()` sends `get_context` push; response is Zod-validated via `SessionContextResponseSchema`
- `setLatestSnapshotLockVersion` clears the cached `versions` array when lock version changes (new save invalidates old history)
- `getLimits(actionType)` fetches plan limits for `new_run`, `activate_workflow`, or `github_sync`
- Listens for `session_context_updated`, `workflow_saved`, `webhook_auth_methods_updated`, `template_updated` channel events

**Commands:** `requestSessionContext`, `requestVersions`, `clearVersions`, `setLatestSnapshotLockVersion`, `getLimits`, `markAIDisclaimerRead`, `setBaseWorkflow`

**Don't use for:** Collaborative workflow data, user presence, credentials, adaptors.

---

### AdaptorStore
**File:** `stores/createAdaptorStore.ts`

**Intent:** Provide the catalog of available NPM adaptors and their versions for job configuration dropdowns. Read-only reference data.

**Key State:** `adaptors` (all system adaptors, sorted by name), `projectAdaptors` (project-installed subset), `isLoading`, `error`

**Key behavior:**
- `requestProjectAdaptors()` returns both project and all adaptors atomically in a single response
- Listens for `adaptors_updated` channel events for real-time list changes
- Each adaptor's versions sorted descending by semver string

**Commands:** `requestAdaptors`, `requestProjectAdaptors`
**Queries:** `findAdaptorByName`, `getLatestVersion`, `getVersions`

---

### CredentialStore
**File:** `stores/createCredentialStore.ts`

**Intent:** Provide available credentials for job configuration, handling the project vs. keychain distinction. Read-only from the client perspective — credential creation/editing happens via server forms.

**Key State:** `projectCredentials`, `keychainCredentials`, `isLoading`, `error`

**Key behavior:**
- Two credential types: project credentials have both `id` and `project_credential_id`; keychain credentials only have `id`
- `findCredentialById(searchId)` checks both ID fields and returns a discriminated union with `type: 'project' | 'keychain'`
- `getCredentialId` returns the appropriate selection ID (`project_credential_id` for project, `id` for keychain)

**Commands:** `requestCredentials`
**Queries:** `findCredentialById`, `credentialExists`, `getCredentialId`

---

### HistoryStore
**File:** `stores/createHistoryStore.ts`

**Intent:** Show workflow execution history and provide detailed run/step inspection with real-time updates for in-progress runs. Manages two distinct views: the history list panel and the run detail viewer.

**Key State:**
- History panel: `history` (top 20 work orders), `isLoading`, `isChannelConnected`
- Run steps cache: `runStepsCache` (keyed by runId), `runStepsSubscribers`, `runStepsLoading`
- Active run viewer: `activeRunId`, `activeRun` (full detail with steps), `activeRunChannel` (dedicated `run:{id}` Phoenix channel), `selectedStepId`

**Key behavior:**
- **Subscription-based cache**: `subscribeToRunSteps(runId, subscriberId)` tracks which components want step data; auto-fetches on first subscription; does NOT clear cache on last unsubscribe (prevents React StrictMode double-mount issues)
- **Dedicated run channel**: `_viewRun` creates a separate `run:{id}` Phoenix channel with guards for idempotency, stale response detection, and channel switching
- **Real-time step updates**: `step:started` and `step:completed` events update both `activeRun.steps` and `runStepsCache` in the same Immer transaction
- **Cache invalidation**: when a run reaches a final state AND has active subscribers, the cache entry is invalidated and refetched
- Supports pre-population: `StoreProvider` can pass `initialRunData` parsed from server-rendered data attributes (for `?run=xxx` URL loads)

**Commands:** `requestHistory`, `requestRunSteps`, `subscribeToRunSteps`, `unsubscribeFromRunSteps`, `selectStep`
**Internal:** `_viewRun`, `_closeRunViewer`, `_switchingFromRun`

---

### UIStore
**File:** `stores/createUIStore.ts`

**Intent:** Coordinate which panels and modals are visible. Pure local state — no network, no persistence. The traffic controller for editor UI layout.

**Key State:** `runPanelOpen`/`runPanelContext`, `githubSyncModalOpen`, `aiAssistantPanelOpen`/`aiAssistantInitialMessage`, `createWorkflowPanelCollapsed`, `templatePanel` (templates list, search, selection), `importPanel` (YAML content, import state machine)

**Key behavior:**
- Reads URL search parameters during initialization: `?chat=true` opens AI panel, `?method=...` expands create-workflow panel
- AI panel takes priority when both URL params are present

**Commands:** `openRunPanel`, `closeRunPanel`, `openGitHubSyncModal`, `closeGitHubSyncModal`, `openAIAssistantPanel`, `closeAIAssistantPanel`, `toggleAIAssistantPanel`, `setTemplates`, `selectTemplate`, `setImportYamlContent`, `setImportState`

---

### EditorPreferencesStore
**File:** `stores/createEditorPreferencesStore.ts`

**Intent:** Remember user's editor layout preferences across page loads via localStorage. The smallest store.

**Key State:** `historyPanelCollapsed` (default: `true`)

**Key behavior:**
- Reads/writes localStorage via `lib0/storage` with key prefix `lightning.editor.`
- Every command persists immediately after updating Immer state

**Commands:** `setHistoryPanelCollapsed`, `resetToDefaults`

---

### AIAssistantStore
**File:** `stores/createAIAssistantStore.ts`

**Intent:** Manage AI assistant chat sessions, messages, and collaborative AI use. Supports multiple users viewing the same session, with send-blocking while AI is responding.

**Key State:** `connectionState` (`disconnected`/`connecting`/`connected`), `sessionId`, `sessionType` (`job_code`/`workflow_template`), `messages`, `isLoading`/`isSending`, `sessionList`/`sessionListLoading`/`sessionListPagination`, `jobCodeContext`/`workflowTemplateContext`, `hasReadDisclaimer`

**Key behavior:**
- Two initialization paths: `connect()` (UI-initiated session creation) and `_initializeContext` (context setup before channel join)
- `_connectChannel` listens for `ai_session_created` on the workflow channel — when another user creates a session, it's prepended to the local session list
- Message deduplication via ID check before adding
- `disconnect()` preserves `sessionId` and `messages` for reconnection continuity
- `loadSessionList` is the only store method using `fetch` API directly (HTTP, not Channel)
- `_setProcessingState(isProcessing)` blocks input for ALL users viewing the session during AI response generation
- Actual AI channel management is handled externally by `useAIAssistantChannel` hook; this store only manages the state

**Commands:** `connect`, `disconnect`, `setMessageSending`, `retryMessage`, `markDisclaimerRead`, `clearSession`, `loadSession`, `loadSessionList`, `updateContext`

---

## Shared Utilities

### common.ts
`createWithSelector(getSnapshot)` — Memoized selector factory. Caches last result + last state; only re-runs selector when state reference changes. Every store uses this.

### devtools.ts
`wrapStoreWithDevTools(config)` — Redux DevTools integration. Serializes state excluding circular references (`ydoc`, `provider`, `rawAwareness`, `userCache`). No-op in production. Used internally by all stores.

---

## Decision Tree: "Where Should This State Go?"

| Question | Store |
|----------|-------|
| Collaborative workflow data (jobs, triggers, edges, positions)? | **WorkflowStore** |
| User presence, cursors, selections? | **AwarenessStore** |
| Connection/sync infrastructure? | **SessionStore** |
| Who am I, what project, what permissions? | **SessionContextStore** |
| Adaptor catalog for job config? | **AdaptorStore** |
| Credential catalog for job config? | **CredentialStore** |
| Execution history, run inspection? | **HistoryStore** |
| AI assistant chat sessions? | **AIAssistantStore** |
| Panel/modal visibility, template browsing? | **UIStore** |
| Persistent user layout preferences? | **EditorPreferencesStore** |
| Temporary component-local UI state? | `useState` / `useReducer` |
| Derived/computed data from existing state? | Selectors on existing stores |

---

## Store Update Patterns

### Pattern 1: Y.Doc → Observer → Immer → Notify
**Used by:** WorkflowStore (jobs/triggers/edges/positions), AwarenessStore (user presence)
```
User edits → Y.Doc transaction → observeDeep fires → produce(state, draft => ...) → notify()
```

### Pattern 2: Command → Y.Doc + Immediate Immer
**Used by:** WorkflowStore (selections + Y.Doc writes), AwarenessStore (local cursor)
```
Command → write to Y.Doc/Awareness → produce() for immediate UI → notify()
(Observer also fires but state already matches = idempotent)
```

### Pattern 3: Channel → Zod → Immer → Notify
**Used by:** SessionContextStore, AdaptorStore, CredentialStore, HistoryStore, AIAssistantStore
```
Channel event/reply → Zod schema validation → produce(state, draft => ...) → notify()
```

### Pattern 4: Direct Immer → Notify (local-only)
**Used by:** UIStore, EditorPreferencesStore, WorkflowStore (selection state)
```
Command → produce(state, draft => ...) → notify() [+ optional localStorage write]
```

---

## When to Create a New Store

**Create a NEW store when:**
1. New domain of data with independent lifecycle
2. Different data source pattern (new Y.Doc structure, new channel event stream)
3. Mixing unrelated responsibilities into an existing store (5+ unrelated concerns)
4. High-frequency updates would cause unnecessary re-renders in unrelated UI

**DON'T create a new store when:**
1. Data is closely related to an existing store's domain
2. It's component-local UI state (`useState`)
3. It's derived/computed from existing state (use selectors)

---

## Store Creation Checklist

```typescript
// 1. Define types
interface MyState { /* ... */ }
interface MyStore { subscribe, getSnapshot, withSelector, /* commands */, /* queries */ }

// 2. Create factory function
export const createMyStore = () => {
  let state: MyState = produce({ /* initial */ }, draft => draft);

  const listeners = new Set<() => void>();
  const notify = () => listeners.forEach(l => l());
  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  };

  const getSnapshot = () => state;
  const withSelector = createWithSelector(getSnapshot);

  // Commands (mutations) - always use produce() + notify()
  const updateSomething = (data) => {
    state = produce(state, draft => { draft.something = data; });
    notify();
  };

  return { subscribe, getSnapshot, withSelector, updateSomething };
};
```

3. Add to `StoreProvider.tsx` `useState` initializer
4. Create hooks in `hooks/useMyStore.ts`
5. Follow Command Query Separation (CQS)
6. Use appropriate update pattern (see above)

---

## Key Architectural Principles

1. **Command Query Separation** — Mutations and reads are separate methods
2. **Referential Stability** — Immer + `createWithSelector` for optimal React performance
3. **Single Responsibility** — Each store manages one domain of data
4. **Type Safety** — Zod for runtime validation at network boundaries, TypeScript for compile-time
5. **useSyncExternalStore** — All stores implement React 18's external store contract
6. **Immutability** — All state updates via Immer's `produce()`

---

## Common Anti-Patterns

- Mixing collaborative and reference data in one store — split by data source
- Creating a store for component-local state — use `useState`
- Skipping `createWithSelector` — causes unnecessary re-renders
- Updating state without `produce()` — breaks referential stability
- Commands that don't call `notify()` — React won't re-render
- Queries with side effects — violates CQS

---

## Related Files

- **Store Implementations:** `assets/js/collaborative-editor/stores/`
- **Store Hooks:** `assets/js/collaborative-editor/hooks/`
- **Store Context:** `assets/js/collaborative-editor/contexts/StoreProvider.tsx`
- **Type Definitions:** `assets/js/collaborative-editor/types/`
