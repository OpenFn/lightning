# Yex (Y.js/Elixir) Usage Guidelines for Lightning

This document provides comprehensive guidelines for working with Yex, the Elixir wrapper for the Y.js CRDT library, in the Lightning collaborative editing system.

## Table of Contents
- [Transaction Deadlock Rules](#transaction-deadlock-rules)
- [The Correct Pattern](#the-correct-pattern)
- [Core Concepts](#core-concepts)
- [Prelim Types](#prelim-types)
- [API Reference](#api-reference)
- [Common Gotchas](#common-gotchas)
- [Testing Patterns](#testing-patterns)

---

## Transaction Deadlock Rules

### Retrieve objects before transactions

Retrieve Yex objects (maps, arrays, text) before starting a transaction.

Calling `Yex.Doc.get_map/2`, `Yex.Doc.get_array/2`, or `Yex.Doc.get_text/2` **inside a transaction will hang the BEAM VM**.

### Why this happens

From `/deps/y_ex/lib/doc.ex:6-8`:

> It is not recommended to perform operations on a single document from multiple processes simultaneously.
> If blocked by a transaction, the Beam scheduler threads may potentially deadlock.
> This limitation is due to the underlying yrs and beam specifications and may be resolved in the future.

The underlying issue:
1. Yex documents are owned by a worker process (usually a GenServer)
2. All operations dispatch to this worker process via `GenServer.call`
3. Transactions hold native (Rust) locks in the underlying yrs library
4. If you call `get_map/get_array` inside a transaction, it tries to dispatch to the worker process that's already blocked holding the transaction
5. This creates a deadlock at the BEAM scheduler level, **hanging the entire VM**

---

## The Correct Pattern

### ✅ DO THIS

```elixir
def serialize_to_ydoc(doc, workflow) do
  # Step 1: Get ALL Yex objects BEFORE the transaction
  workflow_map = Yex.Doc.get_map(doc, "workflow")
  jobs_array = Yex.Doc.get_array(doc, "jobs")
  edges_array = Yex.Doc.get_array(doc, "edges")
  triggers_array = Yex.Doc.get_array(doc, "triggers")
  positions = Yex.Doc.get_map(doc, "positions")

  # Step 2: Start transaction and use the pre-retrieved objects
  Yex.Doc.transaction(doc, "initialize_workflow_document", fn ->
    Yex.Map.set(workflow_map, "id", workflow.id)
    Yex.Map.set(workflow_map, "name", workflow.name || "")

    initialize_jobs(jobs_array, workflow.jobs)
    initialize_edges(edges_array, workflow.edges)
    initialize_triggers(triggers_array, workflow.triggers)
    initialize_positions(positions, workflow.positions)
  end)

  doc
end
```

**Reference:** `lib/lightning/collaboration/workflow_serializer.ex:54-70`

### ❌ DON'T DO THIS

```elixir
def serialize_to_ydoc(doc, workflow) do
  # ❌ WRONG: Getting objects inside transaction will hang the VM
  Yex.Doc.transaction(doc, "initialize_workflow_document", fn ->
    workflow_map = Yex.Doc.get_map(doc, "workflow")  # DEADLOCK!
    jobs_array = Yex.Doc.get_array(doc, "jobs")      # DEADLOCK!

    Yex.Map.set(workflow_map, "id", workflow.id)
    # ...
  end)
end
```

---

## Core Concepts

### Critical: You Cannot Create Map/Array/Text Directly

Yex.Map, Yex.Array, and Yex.Text **cannot be created directly**. They can only be obtained through `Yex.Doc.get_map/2`, `Yex.Doc.get_array/2`, and `Yex.Doc.get_text/2`.

```elixir
# ❌ WRONG - These functions DO NOT EXIST
map = Yex.Map.new()          # NO! This function doesn't exist
array = Yex.Array.new()      # NO! This function doesn't exist
text = Yex.Text.new()        # NO! This function doesn't exist

# ✅ CORRECT - Only way to create these types
doc = Yex.Doc.new()
map = Yex.Doc.get_map(doc, "my_map")       # This is the ONLY way
array = Yex.Doc.get_array(doc, "my_array") # This is the ONLY way
text = Yex.Doc.get_text(doc, "my_text")    # This is the ONLY way
```

**To insert nested structures (a map inside an array, etc), use Prelim types:**

```elixir
# ❌ WRONG - You cannot insert a Yex.Map/Array/Text that doesn't exist
jobs_array = Yex.Doc.get_array(doc, "jobs")
job_map = Yex.Map.new()  # ERROR! This function doesn't exist
Yex.Array.push(jobs_array, job_map)

# ✅ CORRECT - Use Prelim types for nested structures
jobs_array = Yex.Doc.get_array(doc, "jobs")
job_map = Yex.MapPrelim.from(%{
  "id" => "abc123",
  "name" => "My Job",
  "body" => Yex.TextPrelim.from("console.log('hello');")
})
Yex.Array.push(jobs_array, job_map)

# After insertion, prelim becomes real Yex type
{:ok, real_job_map} = Yex.Array.fetch(jobs_array, 0)
# real_job_map is now a %Yex.Map{} struct
{:ok, body_text} = Yex.Map.fetch(real_job_map, "body")
# body_text is now a %Yex.Text{} struct
```

**Why this matters:**
- Yex types are bound to a document and worker process
- They require a transaction context to operate
- Prelim types are "plans" that become real Yex types when inserted
- This is different from typical Elixir APIs where you can create structs directly

**Reference:** `deps/y_ex/lib/doc.ex:113-135`, `lib/lightning/collaboration/workflow_serializer.ex:114-127`

---

### Worker Process Model

Every `Yex.Doc` has a `worker_pid` field that identifies which process owns the document.

```elixir
# Creating a document sets worker_pid to self() by default
doc = Yex.Doc.new()  # worker_pid = self()

# Or explicitly specify the worker process
doc = Yex.Doc.new(some_genserver_pid)
```

**Key Points:**
- All operations automatically dispatch to the worker process via `GenServer.call`
- If the current process IS the worker process, operations execute directly
- This ensures thread safety but requires careful transaction handling

**Required GenServer Handler:**

If you pass a doc to another process, that process must handle this message:

```elixir
@impl true
def handle_call({Yex.Doc, :run, fun}, _from, state) do
  {:reply, fun.(), state}
end
```

**Reference:** `deps/y_ex/lib/server/doc_server_worker.ex:125-130`

### Transactions

Transactions bundle multiple operations into a single atomic update.

```elixir
# With a transaction name (recommended for debugging)
Yex.Doc.transaction(doc, "update_workflow", fn ->
  Yex.Map.set(map, "key", "value")
  Yex.Array.push(array, item)
  # All operations bundled into one update
end)

# Without a name
Yex.Doc.transaction(doc, fn ->
  # Operations...
end)
```

**Important Transaction Rules:**
1. **Cannot be nested** - Attempting to start a transaction inside another raises: "Transaction already in progress"
2. **Get objects BEFORE transaction** - Critical for avoiding deadlocks
3. **All operations are atomic** - Either all succeed or all fail
4. **Single update broadcast** - All changes in transaction trigger one update event

**Reference:** `deps/y_ex/lib/doc.ex:145-181`

### Document Structure in Lightning

Lightning workflows use a consistent Y.Doc structure:

```elixir
# Root-level collections
"workflow"  (Yex.Map)   - Workflow metadata: %{"id" => ..., "name" => ...}
"jobs"      (Yex.Array) - Array of job maps with Y.Text body
"edges"     (Yex.Array) - Array of edge maps
"triggers"  (Yex.Array) - Array of trigger maps
"positions" (Yex.Map)   - Node positions: %{node_id => %{"x" => ..., "y" => ...}}
```

**Reference:** `lib/lightning/collaboration/workflow_serializer.ex:11-28`

---

## API Reference

For the full library API (map/array/text methods, document options, state encoding, subscriptions) see `deps/y_ex/lib/`. This section covers only Lightning-specific usage patterns; the rules in [Transaction Deadlock Rules](#transaction-deadlock-rules) and [Prelim Types](#prelim-types) apply throughout.

### Getting root collections

Always get these **before** transactions (see deadlock rules above):

```elixir
workflow_map = Yex.Doc.get_map(doc, "workflow")
jobs_array = Yex.Doc.get_array(doc, "jobs")
text = Yex.Doc.get_text(doc, "content")
```

These functions create the collection if it doesn't exist.

## Prelim Types

When inserting complex objects into arrays or maps, use `Prelim` types. `Yex.Map`, `Yex.Array`, and `Yex.Text` cannot be constructed directly — they only come from `Yex.Doc.get_*` — so nested structures are built via `MapPrelim`, `ArrayPrelim`, and `TextPrelim`. On insertion the prelim becomes the real Yex type.

```elixir
# Map prelim inserted into an array (typical Lightning job insert)
job_map = Yex.MapPrelim.from(%{
  "id" => "abc123",
  "name" => "My Job",
  "body" => Yex.TextPrelim.from("console.log('hello');"),
  "adaptor" => "@openfn/language-common@1.0.0"
})

Yex.Array.push(jobs_array, job_map)

# Array prelim inserted into a map
array_prelim = Yex.ArrayPrelim.from([1, 2, 3, 4])
Yex.Map.set(map, "numbers", array_prelim)

# After insertion the prelim becomes a real Yex type
{:ok, job} = Yex.Array.fetch(jobs_array, 0)
# job["body"] is a %Yex.Text{} struct
```

**Reference:** `lib/lightning/collaboration/workflow_serializer.ex:114-127`

### Extracting Data

```elixir
# Extract workflow data from Y.Doc
workflow_map = Yex.Doc.get_map(doc, "workflow")
jobs_array = Yex.Doc.get_array(doc, "jobs")

# Simple values
id = Yex.Map.fetch!(workflow_map, "id")
name = Yex.Map.fetch!(workflow_map, "name")

# Convert arrays to lists
jobs_list = Yex.Array.to_json(jobs_array)  # Returns list of maps

# Process each item
jobs = Enum.map(jobs_list, fn job ->
  %{
    "id" => job["id"],
    "name" => job["name"],
    "body" => extract_text_field(job["body"])  # Handle Text type
  }
end)

# Helper for extracting text fields
defp extract_text_field(%Yex.Text{} = text), do: Yex.Text.to_string(text)
defp extract_text_field(string) when is_binary(string), do: string
defp extract_text_field(nil), do: ""
```

**Reference:** `lib/lightning/collaboration/workflow_serializer.ex:172-217`

### Subscribing to document updates

For state sync and update propagation APIs (`Yex.apply_update/2`, `Yex.encode_state_as_update/1`, `Yex.Doc.monitor_update/2`, `Yex.Doc.demonitor_update/1`), see `deps/y_ex/lib/y_ex.ex` and `deps/y_ex/lib/doc.ex`. Lightning-specific rule: always unsubscribe in your GenServer's `terminate/2` callback — see Gotcha #2 below.

---

## Common Gotchas

### 1. Nested Transactions Not Allowed

**Problem:** Transactions cannot be nested.

**Solution:** Structure your code to use a single transaction.

```elixir
# ❌ Wrong - raises "Transaction already in progress"
Yex.Doc.transaction(doc, fn ->
  Yex.Map.set(map, "outer", "value")

  Yex.Doc.transaction(doc, fn ->  # ERROR!
    Yex.Map.set(map, "inner", "value")
  end)
end)

# ✅ Correct - single transaction
Yex.Doc.transaction(doc, fn ->
  Yex.Map.set(map, "outer", "value")
  Yex.Map.set(map, "inner", "value")
end)
```

### 2. Forgetting to Unsubscribe from Updates

**Problem:** Subscriptions stored in process dictionary will leak memory if not cleaned up.

**Solution:** Always unsubscribe in `terminate/2` callback.

```elixir
def init(_opts) do
  doc = get_doc_somehow()
  {:ok, sub_ref} = Yex.Doc.monitor_update(doc)
  {:ok, %{doc: doc, sub_ref: sub_ref}}
end

# ✅ Clean up subscription
def terminate(_reason, state) do
  Yex.Doc.demonitor_update(state.sub_ref)
  :ok
end
```

**Reference:** `deps/y_ex/lib/subscription.ex:49-78`

### 3. Converting Atoms to Strings for Yjs Compatibility

**Problem:** Yjs only supports boolean, string, number, and null. Elixir atoms must be converted.

**Solution:** Convert atoms (except booleans) to strings.

```elixir
# ✅ Correct - convert atoms to strings
edge_map = Yex.MapPrelim.from(%{
  "condition_type" => edge.condition_type |> to_string(),  # :always -> "always"
  "type" => trigger.type |> to_string(),                   # :webhook -> "webhook"
  "enabled" => edge.enabled                                # boolean stays as-is
})

# Helper function
defp to_yjs_variant(value) when is_boolean(value), do: value
defp to_yjs_variant(value) when is_atom(value), do: value |> to_string()
defp to_yjs_variant(value), do: value
```

**Reference:** `lib/lightning/collaboration/workflow_reconciler.ex:236-240`

### 4. Text Fields Need Special Extraction

**Problem:** Y.Text fields don't automatically convert to strings.

**Solution:** Use `Yex.Text.to_string/1` to extract text content.

```elixir
# After calling Yex.Array.to_json(jobs_array)
jobs = Enum.map(jobs_list, fn job ->
  %{
    "id" => job["id"],
    "body" => extract_text(job["body"])  # Don't forget this!
  }
end)

defp extract_text(%Yex.Text{} = text), do: Yex.Text.to_string(text)
defp extract_text(binary) when is_binary(binary), do: binary
defp extract_text(nil), do: ""
```

**Reference:** `lib/lightning/collaboration/workflow_serializer.ex:212-217`

### 5. Using Deprecated Functions

**Problem:** `Yex.Map.get/2` and `Yex.Array.get/2` are deprecated.

**Solution:** Use `fetch/2` or `fetch!/2` instead.

```elixir
# ❌ Deprecated
{:ok, value} = Yex.Map.get(map, "key")

# ✅ Use these instead
{:ok, value} = Yex.Map.fetch(map, "key")
value = Yex.Map.fetch!(map, "key")  # Raises if not found
```

**Reference:** `deps/y_ex/lib/shared_type/map.ex:83-87`

### 6. Nil Values in Job/Edge Fields

**Problem:** Some fields can be nil and need special handling.

**Solution:** Use `|| ""` for text fields, leave others as nil.

```elixir
job_map = Yex.MapPrelim.from(%{
  "name" => job.name || "",                      # Convert nil to empty string
  "body" => Yex.TextPrelim.from(job.body || ""), # Convert nil to empty string
  "adaptor" => job.adaptor,                      # Can be nil
  "project_credential_id" => job.project_credential_id  # Can be nil
})
```

**Reference:** `lib/lightning/collaboration/workflow_serializer.ex:116-124`

### 7. Finding Array Items by ID

**Problem:** Arrays don't have a direct "find by ID" method.

**Solution:** Use `Enum.find` with the array (it implements Enumerable).

```elixir
# Find item in array by ID
item = Enum.find(jobs_array, fn job ->
  Yex.Map.fetch!(job, "id") == target_id
end)

# Find index
index = Enum.find_index(jobs_array, fn job ->
  Yex.Map.fetch!(job, "id") == target_id
end)
```

**Reference:** `lib/lightning/collaboration/workflow_reconciler.ex:222-234`

---

## Testing Patterns

### Creating Test Documents

```elixir
test "serialize workflow to Y.Doc" do
  workflow = insert(:workflow, name: "Test")

  # Create a fresh document for testing
  doc = Yex.Doc.new()

  WorkflowSerializer.serialize_to_ydoc(doc, workflow)

  # Verify the result
  workflow_map = Yex.Doc.get_map(doc, "workflow")
  assert Yex.Map.fetch!(workflow_map, "name") == "Test"
end
```

**Reference:** `test/lightning/collaboration/workflow_serializer_test.exs:21-26`

### Monitoring Updates in Tests

```elixir
test "transaction triggers single update" do
  doc = Yex.Doc.new()
  map = Yex.Doc.get_map(doc, "test")

  # Subscribe to updates
  Yex.Doc.monitor_update(doc)

  # Perform transaction
  Yex.Doc.transaction(doc, fn ->
    Yex.Map.set(map, "key1", "value1")
    Yex.Map.set(map, "key2", "value2")
  end)

  # Assert exactly one update
  assert_receive {:update_v1, _update, _origin, ^doc}
  refute_receive {:update_v1, _, _, ^doc}, nil, "Expected only one update"
end
```

**Reference:** `test/lightning/collaboration/workflow_reconciler_test.exs:72-77`

### Testing Round-Trip Serialization

```elixir
test "round-trip: serialize then deserialize" do
  workflow = insert(:complex_workflow)

  doc = Yex.Doc.new()

  # Serialize
  WorkflowSerializer.serialize_to_ydoc(doc, workflow)

  # Deserialize
  extracted = WorkflowSerializer.deserialize_from_ydoc(doc, workflow.id)

  # Verify data matches
  assert extracted["name"] == workflow.name
  assert length(extracted["jobs"]) == length(workflow.jobs)

  # Verify field conversions
  Enum.zip(extracted["jobs"], workflow.jobs)
  |> Enum.each(fn {extracted_job, original_job} ->
    assert extracted_job["name"] == original_job.name
    assert extracted_job["body"] == original_job.body
  end)
end
```

**Reference:** `test/lightning/collaboration/workflow_serializer_test.exs:662-776`

### Helper Functions for Tests

```elixir
# Preload workflow associations
defp preload_workflow_associations(workflow) do
  Repo.preload(workflow, [:jobs, :edges, :triggers])
end

# Find item in Y.Array by ID
defp find_in_ydoc_array(array, id) do
  array
  |> Enum.find(fn item ->
    case item do
      %Yex.Map{} = map -> Yex.Map.fetch!(map, "id") == id
      map when is_map(map) -> Map.get(map, "id") == id
    end
  end)
end

# Assert single update
defp assert_one_update(doc) do
  assert_receive {:update_v1, _, nil, ^doc}
  refute_receive {:update_v1, _, nil, ^doc}, nil, "Got a second update"
end
```

---

## Summary

The two rules that prevent VM-level failures: get Yex objects before starting a transaction (deadlock risk), and don't try to construct Map/Array/Text directly — use `Yex.Doc.get_*` or Prelim types. Beyond those, prefer `fetch/2` over deprecated `get/2`, convert non-boolean atoms to strings, extract `Yex.Text` with `to_string/1`, and unsubscribe from `monitor_update` in `terminate/2`.

---

## References

- **Yex Library:** `deps/y_ex/lib/`
- **Collaboration Module:** `lib/lightning/collaboration/`
- **WorkflowSerializer:** `lib/lightning/collaboration/workflow_serializer.ex`
- **Session:** `lib/lightning/collaboration/session.ex`
- **Tests:** `test/lightning/collaboration/`

---

## Questions or Issues?

If you encounter issues or have questions:
1. Check this guide first
2. Review the code references provided
3. Look at test files for working examples
4. Get objects before transactions
