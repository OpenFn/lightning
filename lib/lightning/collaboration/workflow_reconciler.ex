defmodule Lightning.Collaboration.WorkflowReconciler do
  @moduledoc """
  Handles reconciliation of workflow changes between LiveView saves and
  collaborative YDoc instances. Converts Ecto changeset operations to
  YDoc-compatible operations and applies them to any running SharedDoc.
  """
  import Ecto.Changeset, only: [get_field: 2]

  alias Lightning.Collaboration.Session
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow
  alias Yex.Doc
  alias Yex.Sync.SharedDoc

  require Logger

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
      ~w(id cron_expression enabled has_auth_method type)a |> pluck_fields(cs)

    {:insert, Doc.get_array(doc, "triggers"), data}
  end

  defp to_operation(
         %Ecto.Changeset{action: :update, data: %Trigger{}} = cs,
         doc,
         _workflow
       ) do
    changes =
      ~w(cron_expression enabled has_auth_method type)a |> pluck_fields(cs)

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
