defmodule Lightning.Collaboration.WorkflowReconciler do
  @moduledoc """
  Handles reconciliation of workflow changes between LiveView saves and
  collaborative YDoc instances. Converts Ecto changeset operations to
  YDoc-compatible operations and applies them to any running SharedDoc.
  """
  import Ecto.Changeset, only: [get_field: 2]

  alias Lightning.Collaboration.Session
  alias Lightning.Collaboration.WorkflowSerializer
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow
  alias Yex.Doc
  alias Yex.Sync.SharedDoc

  require Logger

  defmodule ReconcileRequested do
    @moduledoc """
    Broadcast on a workflow's collaboration topic to ask the process that owns
    the live SharedDoc to re-sync it from the database. Published by out-of-band
    writers (the provisioner import path) after their transaction commits.
    """
    @enforce_keys [:workflow_id]
    defstruct [:workflow_id]
  end

  @doc """
  Takes a changeset that was used to update a workflow and reconciles it with
  the active SharedDocs for that workflow.

  Note: This always reconciles to the latest (unversioned) document only.
  Versioned snapshots (e.g., "workflow:123:v22") are read-only historical views
  and should never receive live updates from saves.
  """
  @spec reconcile_workflow_changes(Ecto.Changeset.t(), Workflow.t()) :: :ok
  def reconcile_workflow_changes(%Ecto.Changeset{} = changeset, workflow) do
    # Always reconcile to the latest (unversioned) document
    # Format: "workflow:123" (not "workflow:123:v22")
    document_name = "workflow:#{workflow.id}"

    case Session.lookup_shared_doc(document_name) do
      nil ->
        Logger.debug(
          "No active SharedDoc for workflow #{workflow.id}, skipping reconciliation"
        )

      shared_doc_pid ->
        SharedDoc.update_doc(shared_doc_pid, fn doc ->
          changeset
          |> generate_ydoc_operations(workflow, doc)
          |> apply_operations(doc)
        end)
    end

    # TODO: Send a message to all sessions that the workflow has been updated
    # so they can sync their changes

    :ok
  end

  @doc """
  Subscribe the calling process to a workflow's collaboration topic.

  The process that owns the live SharedDoc (the `DocumentSupervisor`) subscribes
  when it starts, so it can reconcile the document in-place when an out-of-band
  writer broadcasts a `ReconcileRequested`.

  Subscribes against `Lightning.PubSub` directly rather than through
  `Lightning.subscribe/1`: the caller is a long-lived background process, not a
  request/LiveView process, so it must not depend on the test-time Lightning
  mock (which is scoped to the test process).
  """
  @spec subscribe(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe(workflow_id) when is_binary(workflow_id) do
    Phoenix.PubSub.subscribe(Lightning.PubSub, topic(workflow_id))
  end

  @doc """
  Ask the owner of each workflow's live SharedDoc to reconcile from the
  database. A no-op for any workflow that has no live document.

  Must be called AFTER the writing transaction has committed: the subscriber
  reloads the workflow through its own database connection, so an event
  published mid-transaction would reconcile against pre-commit state.
  """
  @spec request_reconciliation([Ecto.UUID.t()] | Ecto.UUID.t()) :: :ok
  def request_reconciliation(workflow_ids) when is_list(workflow_ids) do
    Enum.each(workflow_ids, &request_reconciliation/1)
  end

  def request_reconciliation(workflow_id) when is_binary(workflow_id) do
    Lightning.broadcast(
      topic(workflow_id),
      %ReconcileRequested{workflow_id: workflow_id}
    )

    :ok
  end

  @doc """
  Reconcile a workflow's live collaborative document with the current database
  state.

  Looks up the live (unversioned) SharedDoc for the workflow. If none is alive,
  this is a no-op: a cold start self-heals via `Persistence.reconcile_or_reset/3`
  when the document is next opened. Otherwise the document is reset in-place from
  the database (clearing jobs/edges/triggers/positions/errors then re-serialising,
  which also sets `lock_version`), so connected clients receive a live
  incremental sync rather than a teardown.

  The mutation runs inside `SharedDoc.update_doc/2`, i.e. in the process that owns
  the Y.Doc, so no Y.Doc transaction is ever held across a process boundary.
  """
  @spec reconcile_workflow_document(Ecto.UUID.t()) :: :ok
  def reconcile_workflow_document(workflow_id) do
    document_name = "workflow:#{workflow_id}"

    case Session.lookup_shared_doc(document_name) do
      nil ->
        Logger.debug(
          "No active SharedDoc for workflow #{workflow_id}, skipping reconciliation"
        )

        :ok

      shared_doc_pid ->
        case load_workflow(workflow_id) do
          nil ->
            Logger.debug(
              "Workflow #{workflow_id} not found, skipping reconciliation"
            )

            :ok

          workflow ->
            reset_shared_doc(shared_doc_pid, workflow)
            :ok
        end
    end
  end

  defp topic(workflow_id), do: "workflow_collaboration:#{workflow_id}"

  defp load_workflow(workflow_id) do
    Lightning.Workflows.get_workflow(workflow_id,
      include: [:jobs, :edges, :triggers]
    )
  end

  # Full reset from the database, mirroring the lifecycle reset
  # (Session.clear_and_reset_doc / Persistence.clear_and_reset_workflow). All
  # Yex collections are retrieved before the clear transaction to avoid a VM
  # deadlock, and serialize_to_ydoc runs its own transaction afterwards.
  defp reset_shared_doc(shared_doc_pid, workflow) do
    SharedDoc.update_doc(shared_doc_pid, fn doc ->
      jobs_array = Doc.get_array(doc, "jobs")
      edges_array = Doc.get_array(doc, "edges")
      triggers_array = Doc.get_array(doc, "triggers")
      positions_map = Doc.get_map(doc, "positions")
      errors_map = Doc.get_map(doc, "errors")

      Doc.transaction(doc, "reconcile_workflow_document", fn ->
        clear_array(jobs_array)
        clear_array(edges_array)
        clear_array(triggers_array)
        clear_map(positions_map)
        clear_map(errors_map)
      end)

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)
    end)
  end

  defp clear_array(array) do
    length = Yex.Array.length(array)

    if length > 0 do
      Yex.Array.delete_range(array, 0, length)
    end
  end

  defp clear_map(map) do
    map
    |> Yex.Map.to_map()
    |> Enum.each(fn {key, _val} -> Yex.Map.delete(map, key) end)
  end

  defp generate_ydoc_operations(%Ecto.Changeset{} = changeset, workflow, doc) do
    [
      :jobs,
      :edges,
      :triggers,
      :positions,
      :name,
      :concurrency,
      :enable_job_logs,
      :lock_version
    ]
    |> Enum.flat_map(fn assoc ->
      case Ecto.Changeset.get_change(changeset, assoc) do
        nil ->
          []

        # Handle has_many changes (e.g. jobs, edges, triggers)
        changesets when is_list(changesets) ->
          Enum.map(changesets, &to_operation(&1, doc, workflow))

        # Handle jsonb/map changes (e.g. positions)
        changes when is_map(changes) ->
          [{:update, Doc.get_map(doc, to_string(assoc)), changes}]

        # Handle workflow field changes
        change ->
          [
            {:update, Doc.get_map(doc, "workflow"),
             %{to_string(assoc) => change}}
          ]
      end
    end)
  end

  # Job operations
  defp to_operation(
         %Ecto.Changeset{action: :insert, data: %Job{}} = cs,
         doc,
         _workflow
       ) do
    data =
      ~w(id name body adaptor project_credential_id keychain_credential_id)a
      |> pluck_fields(cs)

    {:insert, Doc.get_array(doc, "jobs"), data}
  end

  defp to_operation(
         %Ecto.Changeset{action: :update, data: %Job{}} = cs,
         doc,
         _workflow
       ) do
    item = Doc.get_array(doc, "jobs") |> find_in_array(cs.data.id)

    changes =
      ~w(name body adaptor project_credential_id keychain_credential_id)a
      |> pluck_fields(cs)

    {:update, item, changes}
  end

  defp to_operation(
         %Ecto.Changeset{action: :delete, data: %Job{}} = cs,
         doc,
         _workflow
       ) do
    jobs_array = Doc.get_array(doc, "jobs")

    index = jobs_array |> find_index_in_array(cs.data.id)

    {:delete, jobs_array, index}
  end

  # Edge operations
  defp to_operation(
         %Ecto.Changeset{action: :insert, data: %Edge{}} = cs,
         doc,
         _workflow
       ) do
    data =
      ~w(id condition_expression condition_label condition_type
         enabled source_job_id source_trigger_id target_job_id)a
      |> pluck_fields(cs)

    {:insert, Doc.get_array(doc, "edges"), data}
  end

  defp to_operation(
         %Ecto.Changeset{action: :update, data: %Edge{}} = cs,
         doc,
         _workflow
       ) do
    edge_item = Doc.get_array(doc, "edges") |> find_in_array(cs.data.id)

    changes =
      ~w(condition_expression condition_label condition_type
         enabled source_job_id source_trigger_id target_job_id)a
      |> pluck_fields(cs)

    {:update, edge_item, changes}
  end

  defp to_operation(
         %Ecto.Changeset{action: :delete, data: %Edge{}} = cs,
         doc,
         _workflow
       ) do
    edges_array = Doc.get_array(doc, "edges")

    index = edges_array |> find_index_in_array(cs.data.id)

    {:delete, edges_array, index}
  end

  # Trigger operations
  defp to_operation(
         %Ecto.Changeset{action: :insert, data: %Trigger{}} = cs,
         doc,
         _workflow
       ) do
    data =
      ~w(id cron_expression enabled type)a |> pluck_fields(cs)

    {:insert, Doc.get_array(doc, "triggers"), data}
  end

  defp to_operation(
         %Ecto.Changeset{action: :update, data: %Trigger{}} = cs,
         doc,
         _workflow
       ) do
    changes =
      ~w(cron_expression enabled type)a |> pluck_fields(cs)

    item =
      Doc.get_array(doc, "triggers") |> find_in_array(cs.data.id)

    {:update, item, changes}
  end

  defp to_operation(
         %Ecto.Changeset{action: :delete, data: %Trigger{}} = cs,
         doc,
         _workflow
       ) do
    triggers_array = Doc.get_array(doc, "triggers")

    index = triggers_array |> find_index_in_array(cs.data.id)

    {:delete, triggers_array, index}
  end

  # Fallback
  defp to_operation(_, _, _), do: nil

  defp apply_operations(operations, doc) do
    Doc.transaction(doc, fn ->
      for {action, array_or_item, data} <- operations do
        apply_operation(action, array_or_item, data)
      end
    end)
  end

  defp apply_operation(action, array_or_item, data) do
    case action do
      :insert ->
        Yex.Array.push(array_or_item, data)

      :update ->
        Enum.each(data, fn {key, value} ->
          Yex.Map.set(array_or_item, key, value)
        end)

      :delete ->
        Yex.Array.delete(array_or_item, data)
    end
  end

  defp pluck_fields(fields, cs) do
    fields
    |> Enum.into(%{}, fn field ->
      {field |> to_string(), get_field(cs, field) |> to_yjs_variant()}
    end)
  end

  defp find_index_in_array(array, id) do
    array
    |> Enum.find_index(fn item ->
      Yex.Map.fetch!(item, "id") == id
    end)
  end

  defp find_in_array(array, id) do
    array
    |> Enum.find(fn item ->
      Yex.Map.fetch!(item, "id") == id
    end)
  end

  # Yjs only supports boolean, string, number, and null values
  # Convert atoms to strings, explicitly leaving booleans as is (which are also considered atoms)
  defp to_yjs_variant(value) when is_boolean(value), do: value
  defp to_yjs_variant(value) when is_atom(value), do: value |> to_string()
  defp to_yjs_variant(value), do: value
end
