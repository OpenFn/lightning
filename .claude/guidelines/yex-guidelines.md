# Yex (Y.js/Elixir) Usage Guidelines for Lightning

This document provides comprehensive guidelines for working with Yex, the Elixir wrapper for the Y.js CRDT library, in the Lightning collaborative editing system.

## Table of Contents
- [Critical Warning: VM Deadlock Risk](#critical-warning-vm-deadlock-risk)
- [The Correct Pattern](#the-correct-pattern)
- [Core Concepts](#core-concepts)
- [API Reference](#api-reference)
- [Common Gotchas](#common-gotchas)
- [Quick Reference](#quick-reference)
- [Testing Patterns](#testing-patterns)

---

## Critical Warning: VM Deadlock Risk

### ⚠️ THE MOST IMPORTANT RULE ⚠️

**ALWAYS retrieve Yex objects (maps, arrays, text) BEFORE starting a transaction.**

Calling `Yex.Doc.get_map/2`, `Yex.Doc.get_array/2`, or `Yex.Doc.get_text/2` **inside a transaction will hang the BEAM VM**.

### Why This Happens

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

**⚠️ FUNDAMENTAL API CONSTRAINT ⚠️**

Yex.Map, Yex.Array, and Yex.Text **cannot be created directly**. They can ONLY be obtained through `Yex.Doc.get_map/2`, `Yex.Doc.get_array/2`, and `Yex.Doc.get_text/2`.

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

### Creating Documents

```elixir
# Basic document
doc = Yex.Doc.new()

# Document with specific worker process
doc = Yex.Doc.new(worker_pid)

# Document with options
doc = Yex.Doc.with_options(%Yex.Doc.Options{
  client_id: 12345,
  guid: "unique-id"
})
```

### Getting Root Collections

**Always get these BEFORE transactions:**

```elixir
# Get or create a root-level map
workflow_map = Yex.Doc.get_map(doc, "workflow")

# Get or create a root-level array
jobs_array = Yex.Doc.get_array(doc, "jobs")

# Get or create a root-level text
text = Yex.Doc.get_text(doc, "content")
```

**Note:** These functions create the collection if it doesn't exist.

### Working with Maps

```elixir
# Set a value
Yex.Map.set(map, "key", "value")
Yex.Map.set(map, "number", 42)
Yex.Map.set(map, "nested", %{"foo" => "bar"})

# Get a value (returns {:ok, value} or :error)
{:ok, value} = Yex.Map.fetch(map, "key")

# Get a value (raises if not found)
value = Yex.Map.fetch!(map, "key")

# Check if key exists
Yex.Map.has_key?(map, "key")  # true/false

# Delete a key
Yex.Map.delete(map, "key")

# Convert to Elixir map
elixir_map = Yex.Map.to_map(map)     # Preserves Yex types
json_map = Yex.Map.to_json(map)      # Converts to plain data

# Get size
count = Yex.Map.size(map)
```

**Reference:** `deps/y_ex/lib/shared_type/map.ex`

### Working with Arrays

```elixir
# Insert at index
Yex.Array.insert(array, 0, "value")

# Push to end
Yex.Array.push(array, "value")

# Push to beginning
Yex.Array.unshift(array, "value")

# Insert multiple items
Yex.Array.insert_list(array, 0, [1, 2, 3, 4, 5])

# Get element (returns {:ok, value} or :error)
{:ok, value} = Yex.Array.fetch(array, 0)

# Get element (raises if out of bounds)
value = Yex.Array.fetch!(array, 0)

# Delete element
Yex.Array.delete(array, 0)

# Delete range
Yex.Array.delete_range(array, 0, 5)  # Delete 5 elements starting at 0

# Move element
Yex.Array.move_to(array, from_index, to_index)

# Get length
length = Yex.Array.length(array)

# Convert to list
list = Yex.Array.to_list(array)      # Preserves Yex types
json_list = Yex.Array.to_json(array) # Converts to plain data

# Arrays are Enumerable
Enum.each(array, fn item -> ... end)
Enum.map(array, fn item -> ... end)
Enum.find(array, fn item -> ... end)
```

**Reference:** `deps/y_ex/lib/shared_type/array.ex`

### Working with Text

```elixir
# Get or create text
text = Yex.Doc.get_text(doc, "body")

# Insert text
Yex.Text.insert(text, 0, "Hello")

# Insert with formatting
Yex.Text.insert(text, 0, "Bold", %{"bold" => true})

# Delete text
Yex.Text.delete(text, 0, 5)  # Delete 5 characters starting at 0

# Get length
length = Yex.Text.length(text)

# Convert to string
string = Yex.Text.to_string(text)
```

**Reference:** `deps/y_ex/lib/shared_type/text.ex`

### Creating Nested Structures

When inserting complex objects into arrays or maps, use `Prelim` types:

```elixir
# Create a map to insert into an array
job_map = Yex.MapPrelim.from(%{
  "id" => "abc123",
  "name" => "My Job",
  "body" => Yex.TextPrelim.from("console.log('hello');"),
  "adaptor" => "@openfn/language-common@1.0.0"
})

Yex.Array.push(jobs_array, job_map)

# Create an array to insert into a map
array_prelim = Yex.ArrayPrelim.from([1, 2, 3, 4])
Yex.Map.set(map, "numbers", array_prelim)

# The prelim types become actual Yex types after insertion
{:ok, job} = Yex.Array.fetch(jobs_array, 0)
# job["body"] is now a %Yex.Text{} struct
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

### Document Updates

```elixir
# Apply an update from another client
:ok = Yex.apply_update(doc, binary_update)

# Encode document state as update
{:ok, state_binary} = Yex.encode_state_as_update(doc)
# Or use the bang version
state_binary = Yex.encode_state_as_update!(doc)

# Encode state vector
{:ok, vector_binary} = Yex.encode_state_vector(doc)
vector_binary = Yex.encode_state_vector!(doc)

# Encode only the diff
{:ok, diff} = Yex.encode_state_as_update(doc, other_state_vector)
```

**Reference:** `deps/y_ex/lib/y_ex.ex`

### Monitoring Changes

```elixir
# Subscribe to document updates
{:ok, sub_ref} = Yex.Doc.monitor_update(doc)

# Or with custom metadata
{:ok, sub_ref} = Yex.Doc.monitor_update(doc, metadata: %{user_id: 123})

# Receive update messages
receive do
  {:update_v1, update_binary, origin, metadata} ->
    # Handle update
end

# Unsubscribe
Yex.Doc.demonitor_update(sub_ref)
```

**Important:** Always unsubscribe in your GenServer's `terminate/2` callback to prevent memory leaks.

**Reference:** `deps/y_ex/lib/doc.ex:184-234`

---

## Common Gotchas

### 0. Cannot Create Map/Array/Text Directly (MOST COMMON ERROR)

**Problem:** Attempting to call `Yex.Map.new()`, `Yex.Array.new()`, or `Yex.Text.new()` will fail because these functions don't exist.

**Solution:** Use `Yex.Doc.get_map/2`, `Yex.Doc.get_array/2`, or `Yex.Doc.get_text/2`. For nested structures, use Prelim types.

```elixir
# ❌ Wrong - These functions don't exist
map = Yex.Map.new()
array = Yex.Array.new()

# ✅ Correct - Get from document
doc = Yex.Doc.new()
map = Yex.Doc.get_map(doc, "my_map")
array = Yex.Doc.get_array(doc, "my_array")

# ✅ Correct - For nested structures, use Prelim types
jobs = Yex.Doc.get_array(doc, "jobs")
job = Yex.MapPrelim.from(%{
  "id" => "123",
  "body" => Yex.TextPrelim.from("code here")
})
Yex.Array.push(jobs, job)
```

**Reference:** `deps/y_ex/lib/doc.ex:113-135`

### 1. VM Deadlock from Getting Objects in Transactions

**Problem:** Calling `get_map/get_array/get_text` inside a transaction hangs the VM.

**Solution:** Always get objects before starting the transaction.

```elixir
# ✅ Correct
workflow_map = Yex.Doc.get_map(doc, "workflow")
Yex.Doc.transaction(doc, fn ->
  Yex.Map.set(workflow_map, "key", "value")
end)

# ❌ Wrong - VM DEADLOCK
Yex.Doc.transaction(doc, fn ->
  workflow_map = Yex.Doc.get_map(doc, "workflow")  # HANGS HERE
  Yex.Map.set(workflow_map, "key", "value")
end)
```

### 2. Nested Transactions Not Allowed

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

### 3. Forgetting to Unsubscribe from Updates

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

### 4. Converting Atoms to Strings for Yjs Compatibility

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

### 5. Text Fields Need Special Extraction

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

### 6. Using Deprecated Functions

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

### 7. Nil Values in Job/Edge Fields

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

### 8. Finding Array Items by ID

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

## Quick Reference

### Before Every Transaction

```elixir
# 1. Get ALL Yex objects you'll need
map = Yex.Doc.get_map(doc, "name")
array = Yex.Doc.get_array(doc, "name")
text = Yex.Doc.get_text(doc, "name")

# 2. Start transaction
Yex.Doc.transaction(doc, "operation_name", fn ->
  # 3. Use pre-retrieved objects
  Yex.Map.set(map, "key", "value")
  Yex.Array.push(array, item)
end)
```

### Common Operations Cheat Sheet

```elixir
# Documents
doc = Yex.Doc.new()
doc = Yex.Doc.new(worker_pid)

# Root Collections (BEFORE transactions)
map = Yex.Doc.get_map(doc, "name")
array = Yex.Doc.get_array(doc, "name")
text = Yex.Doc.get_text(doc, "name")

# Maps
Yex.Map.set(map, "key", value)
{:ok, val} = Yex.Map.fetch(map, "key")
val = Yex.Map.fetch!(map, "key")
Yex.Map.delete(map, "key")
elixir_map = Yex.Map.to_json(map)

# Arrays
Yex.Array.push(array, value)
Yex.Array.insert(array, index, value)
{:ok, val} = Yex.Array.fetch(array, index)
Yex.Array.delete(array, index)
list = Yex.Array.to_json(array)
length = Yex.Array.length(array)

# Text
Yex.Text.insert(text, index, "string")
Yex.Text.delete(text, index, length)
string = Yex.Text.to_string(text)

# Prelim Types (for nested structures)
Yex.MapPrelim.from(%{"key" => "value"})
Yex.ArrayPrelim.from([1, 2, 3])
Yex.TextPrelim.from("text content")

# Transactions
Yex.Doc.transaction(doc, "name", fn -> ... end)

# Monitoring
{:ok, ref} = Yex.Doc.monitor_update(doc)
Yex.Doc.demonitor_update(ref)

# Updates
Yex.apply_update(doc, binary)
binary = Yex.encode_state_as_update!(doc)
```

### Type Conversions

```elixir
# Atoms → Strings (except booleans)
"always" = :always |> to_string()
"webhook" = :webhook |> to_string()
true = true  # Booleans stay as-is

# Nil → Empty String (for text fields)
"" = nil || ""

# Y.Text → String
"text" = Yex.Text.to_string(text)

# Yex → Elixir
map = Yex.Map.to_json(yex_map)      # Deep conversion
list = Yex.Array.to_json(yex_array)  # Deep conversion
```

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

## Summary of Critical Rules

1. ⚠️ **NEVER try to create Map/Array/Text directly** - Use `Yex.Doc.get_map/get_array/get_text` or Prelim types
2. ⚠️ **ALWAYS get Yex objects BEFORE transactions** - This is critical to avoid VM deadlocks
3. ✅ Use `fetch/2` or `fetch!/2` - Not deprecated `get/2`
4. ✅ Convert atoms to strings - Except booleans
5. ✅ Handle nil text fields - Use `|| ""`
6. ✅ Extract Text with `to_string/1` - Y.Text doesn't auto-convert
7. ✅ Unsubscribe in terminate - Prevent memory leaks
8. ✅ No nested transactions - Single transaction only
9. ✅ Use MapPrelim/ArrayPrelim - For nested structures in arrays

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
4. Remember: **Get objects BEFORE transactions!**
