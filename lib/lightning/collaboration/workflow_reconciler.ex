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

  @doc """
  Reconciles a running SharedDoc to match the given workflow from the database.

  Unlike reconcile_workflow_changes/2 (which applies a changeset diff), this
  function diffs the current Y.Doc state against the DB state and applies the
  minimal set of targeted operations to bring them into sync.

  Preserves CRDT item identities for unchanged items — only genuinely added,
  removed, or modified items produce new CRDT operations.
  """
  @spec reconcile_to_db_state(pid(), Workflow.t()) :: :ok
  def reconcile_to_db_state(shared_doc_pid, workflow) do
    SharedDoc.update_doc(shared_doc_pid, fn doc ->
      # Get all array/map references BEFORE transaction (NIF worker constraint)
      jobs_array = Doc.get_array(doc, "jobs")
      edges_array = Doc.get_array(doc, "edges")
      triggers_array = Doc.get_array(doc, "triggers")
      workflow_map = Doc.get_map(doc, "workflow")

      # Compute all operations BEFORE transaction (reads Yex.Array.to_json,
      # find_in_array) — these must not run inside a transaction
      jobs_ops =
        build_reconcile_ops(jobs_array, workflow.jobs, &job_struct_fields/1)

      edges_ops =
        build_reconcile_ops(edges_array, workflow.edges, &edge_struct_fields/1)

      triggers_ops =
        build_reconcile_ops(
          triggers_array,
          workflow.triggers,
          &trigger_struct_fields/1
        )

      # Execute ONLY mutations inside the transaction
      Doc.transaction(doc, "reconcile_to_db_state", fn ->
        Enum.each(jobs_ops, &apply_reconcile_op(&1, jobs_array))
        Enum.each(edges_ops, &apply_reconcile_op(&1, edges_array))
        Enum.each(triggers_ops, &apply_reconcile_op(&1, triggers_array))
        Yex.Map.set(workflow_map, "lock_version", workflow.lock_version)
      end)
    end)

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
        prelim_data =
          case Map.fetch(data, "body") do
            {:ok, body} ->
              Map.put(data, "body", Yex.TextPrelim.from(body || ""))

            :error ->
              data
          end

        Yex.Array.push(array_or_item, Yex.MapPrelim.from(prelim_data))

      :update ->
        Enum.each(data, fn
          {"body", new_body} ->
            case Yex.Map.fetch(array_or_item, "body") do
              {:ok, %Yex.Text{} = text} ->
                new_body_str = new_body || ""

                unless Yex.Text.to_string(text) == new_body_str do
                  Yex.Text.delete(text, 0, Yex.Text.length(text))
                  Yex.Text.insert(text, 0, new_body_str)
                end

              _ ->
                :ok
            end

          {key, value} ->
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

  # Diffs a Y.Doc array against a list of DB structs and returns a list of
  # operations to apply:
  #   - Items in Y.Doc but not in DB  → {:delete, index}  (highest index first)
  #   - Items in DB but not in Y.Doc  → {:insert, fields}
  #   - Items in both                 → {:update, map_ref, new_fields}
  #
  # ALL reads (to_json, find_in_array) happen here, OUTSIDE any transaction.
  defp build_reconcile_ops(array, db_items, fields_fn) do
    db_by_id = Map.new(db_items, fn item -> {to_string(item.id), item} end)
    db_ids = Map.keys(db_by_id)

    doc_json = Yex.Array.to_json(array)
    doc_ids = Enum.map(doc_json, & &1["id"])

    deletes =
      doc_ids
      |> Enum.with_index()
      |> Enum.filter(fn {id, _i} -> id not in db_ids end)
      |> Enum.sort_by(fn {_id, i} -> i end, :desc)
      |> Enum.map(fn {_id, i} -> {:delete, i} end)

    inserts =
      db_items
      |> Enum.filter(fn item -> to_string(item.id) not in doc_ids end)
      |> Enum.map(fn item -> {:insert, fields_fn.(item)} end)

    updates =
      db_items
      |> Enum.filter(fn item -> to_string(item.id) in doc_ids end)
      |> Enum.map(fn db_item ->
        map_ref = find_in_array(array, to_string(db_item.id))
        new_fields = fields_fn.(db_item)
        {:update, map_ref, new_fields}
      end)

    deletes ++ inserts ++ updates
  end

  # Mutations executed INSIDE the transaction
  defp apply_reconcile_op({:delete, index}, array) do
    Yex.Array.delete(array, index)
  end

  defp apply_reconcile_op({:insert, fields}, array) do
    prelim_fields =
      case Map.fetch(fields, "body") do
        {:ok, body} ->
          Map.put(fields, "body", Yex.TextPrelim.from(body || ""))

        :error ->
          fields
      end

    Yex.Array.push(array, Yex.MapPrelim.from(prelim_fields))
  end

  defp apply_reconcile_op({:update, map_ref, new_fields}, _array) do
    Enum.each(new_fields, fn
      {"body", new_body} ->
        case Yex.Map.fetch(map_ref, "body") do
          {:ok, %Yex.Text{} = text} ->
            new_body_str = new_body || ""

            unless Yex.Text.to_string(text) == new_body_str do
              Yex.Text.delete(text, 0, Yex.Text.length(text))
              Yex.Text.insert(text, 0, new_body_str)
            end

          _ ->
            :ok
        end

      {key, value} ->
        case Yex.Map.fetch(map_ref, key) do
          {:ok, current} when current != value ->
            Yex.Map.set(map_ref, key, value)

          _ ->
            :ok
        end
    end)
  end

  defp job_struct_fields(%Job{} = job) do
    %{
      "id" => to_string(job.id),
      "name" => job.name,
      "body" => job.body,
      "adaptor" => job.adaptor,
      "project_credential_id" =>
        job.project_credential_id && to_string(job.project_credential_id),
      "keychain_credential_id" =>
        job.keychain_credential_id && to_string(job.keychain_credential_id)
    }
  end

  defp edge_struct_fields(%Edge{} = edge) do
    %{
      "id" => to_string(edge.id),
      "condition_expression" => edge.condition_expression,
      "condition_label" => edge.condition_label,
      "condition_type" => to_yjs_variant(edge.condition_type),
      "enabled" => edge.enabled,
      "source_job_id" => edge.source_job_id && to_string(edge.source_job_id),
      "source_trigger_id" =>
        edge.source_trigger_id && to_string(edge.source_trigger_id),
      "target_job_id" => edge.target_job_id && to_string(edge.target_job_id)
    }
  end

  defp trigger_struct_fields(%Trigger{} = trigger) do
    %{
      "id" => to_string(trigger.id),
      "cron_expression" => trigger.cron_expression,
      "enabled" => trigger.enabled,
      "type" => to_yjs_variant(trigger.type)
    }
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
