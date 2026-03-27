defmodule Lightning.Collaboration.WorkflowReconciler do
  @moduledoc """
  Handles reconciliation of workflow changes between LiveView saves and
  collaborative YDoc instances. Converts Ecto changeset operations to
  YDoc-compatible operations and applies them to any running SharedDoc.
  """
  import Ecto.Changeset, only: [get_field: 2]

  alias Lightning.Collaborate
  alias Lightning.Collaboration.Session
  alias Lightning.Collaboration.WorkflowSerializer
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Triggers.KafkaConfiguration
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
  Reconciles the SharedDoc for a workflow with the current DB state.

  Called after an external write (provisioner import, sandbox merge) has
  already updated the database. Goes through `Collaborate.start/1` regardless
  of whether anyone is online — this is the unified path for both cases:

  - Nobody online: starts a new document, applies the diff, stops. The
    document flushes to DB on shutdown, so the next user opens correct state.
  - Someone online: joins the existing document, applies the diff (broadcast
    to live users in real time), stops. The document stays alive.

  Unlike `reconcile_workflow_changes/2`, this is state-driven: it diffs the
  live Y.Doc against the DB and applies the minimum targeted operations —
  deleting phantom items (e.g. unsaved jobs from open tabs), inserting new
  items, and updating changed items in-place. CRDT IDs are preserved for
  unchanged items.
  """
  @spec reconcile_workflow_from_db(
          Workflow.t(),
          Lightning.Accounts.User.t()
          | Lightning.VersionControl.ProjectRepoConnection.t()
        ) :: :ok
  def reconcile_workflow_from_db(%Workflow{} = workflow, actor) do
    {:ok, session_pid} = Collaborate.start(workflow: workflow, user: actor)

    Session.update_doc(session_pid, fn doc ->
      apply_db_state_to_doc(doc, workflow)
    end)

    Session.stop(session_pid)

    Phoenix.PubSub.broadcast(
      Lightning.PubSub,
      "workflow:collaborate:#{workflow.id}",
      {:workflow_updated_externally, workflow}
    )

    :ok
  rescue
    error ->
      # Intentional: reconciler failure must never fail the provisioner.
      # This also catches Session startup failures (e.g. Collaborate.start
      # returns {:error, _} and the match raises), so the log is the only
      # signal that reconciliation was skipped.
      Logger.error(
        "Failed to reconcile SharedDoc for workflow #{workflow.id}: #{inspect(error)}"
      )

      :ok
  end

  defp apply_db_state_to_doc(doc, workflow) do
    # Step 1: Pre-fetch all root Yex objects BEFORE transaction (avoids VM deadlock)
    workflow_map = Doc.get_map(doc, "workflow")
    jobs_array = Doc.get_array(doc, "jobs")
    edges_array = Doc.get_array(doc, "edges")
    triggers_array = Doc.get_array(doc, "triggers")

    # Step 2: Read current Y.Doc state as plain Elixir lists (still before transaction)
    ydoc_jobs = Yex.Array.to_list(jobs_array)
    ydoc_edges = Yex.Array.to_list(edges_array)
    ydoc_triggers = Yex.Array.to_list(triggers_array)

    # Step 3: Pre-fetch body Y.Text references — must happen before transaction
    body_texts =
      Map.new(ydoc_jobs, fn job_map ->
        id = Yex.Map.fetch!(job_map, "id")
        {:ok, body} = Yex.Map.fetch(job_map, "body")
        {id, body}
      end)

    # Step 4: Compute all operations before opening the transaction
    job_ops = compute_job_ops(jobs_array, ydoc_jobs, workflow.jobs, body_texts)
    edge_ops = compute_edge_ops(edges_array, ydoc_edges, workflow.edges)

    trigger_ops =
      compute_trigger_ops(triggers_array, ydoc_triggers, workflow.triggers)

    # Step 5: Apply everything in ONE transaction
    Doc.transaction(doc, "provisioner_reconcile", fn ->
      update_workflow_metadata(workflow_map, workflow)
      Enum.each(job_ops ++ edge_ops ++ trigger_ops, &apply_reconcile_op/1)
    end)
  end

  defp update_workflow_metadata(workflow_map, workflow) do
    Yex.Map.set(workflow_map, "lock_version", workflow.lock_version)
    Yex.Map.set(workflow_map, "name", workflow.name || "")
    Yex.Map.set(workflow_map, "concurrency", workflow.concurrency)
    Yex.Map.set(workflow_map, "enable_job_logs", workflow.enable_job_logs)

    Yex.Map.set(
      workflow_map,
      "deleted_at",
      WorkflowSerializer.datetime_to_string(workflow.deleted_at)
    )
  end

  # ---------------------------------------------------------------------------
  # Job operations
  # ---------------------------------------------------------------------------

  defp compute_job_ops(jobs_array, ydoc_jobs, db_jobs, body_texts) do
    ydoc_ids = ydoc_jobs |> Enum.map(&Yex.Map.fetch!(&1, "id")) |> MapSet.new()
    db_ids = db_jobs |> Enum.map(& &1.id) |> MapSet.new()

    phantom_ids = MapSet.difference(ydoc_ids, db_ids)
    new_ids = MapSet.difference(db_ids, ydoc_ids)
    existing_ids = MapSet.intersection(ydoc_ids, db_ids)

    delete_ops =
      phantom_ids
      |> Enum.map(&find_index_in_array(jobs_array, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort(:desc)
      |> Enum.map(&{:delete, jobs_array, &1})

    insert_ops =
      db_jobs
      |> Enum.filter(&MapSet.member?(new_ids, &1.id))
      |> Enum.map(&{:insert, jobs_array, job_to_prelim(&1)})

    update_ops =
      db_jobs
      |> Enum.filter(&MapSet.member?(existing_ids, &1.id))
      |> Enum.flat_map(fn db_job ->
        ydoc_job = Enum.find(ydoc_jobs, &(Yex.Map.fetch!(&1, "id") == db_job.id))
        body_text = Map.get(body_texts, db_job.id)
        job_update_ops(ydoc_job, body_text, db_job)
      end)

    delete_ops ++ insert_ops ++ update_ops
  end

  defp job_to_prelim(job) do
    Yex.MapPrelim.from(%{
      "id" => job.id,
      "name" => job.name || "",
      "body" => Yex.TextPrelim.from(job.body || ""),
      "adaptor" => job.adaptor,
      "project_credential_id" => job.project_credential_id,
      "keychain_credential_id" => job.keychain_credential_id
    })
  end

  defp job_update_ops(ydoc_job, body_text, db_job) do
    field_ops =
      [
        {"name", db_job.name || ""},
        {"adaptor", db_job.adaptor},
        {"project_credential_id", db_job.project_credential_id},
        {"keychain_credential_id", db_job.keychain_credential_id}
      ]
      |> Enum.flat_map(fn {key, db_val} ->
        case Yex.Map.fetch(ydoc_job, key) do
          {:ok, ^db_val} -> []
          _ -> [{:set_field, ydoc_job, key, db_val}]
        end
      end)

    body_ops =
      case body_text do
        %Yex.Text{} = text ->
          db_body = db_job.body || ""
          current = Yex.Text.to_string(text)
          if current != db_body, do: [{:update_text, text, db_body}], else: []

        _ ->
          []
      end

    field_ops ++ body_ops
  end

  # ---------------------------------------------------------------------------
  # Edge operations
  # ---------------------------------------------------------------------------

  defp compute_edge_ops(edges_array, ydoc_edges, db_edges) do
    ydoc_ids = ydoc_edges |> Enum.map(&Yex.Map.fetch!(&1, "id")) |> MapSet.new()
    db_ids = db_edges |> Enum.map(& &1.id) |> MapSet.new()

    phantom_ids = MapSet.difference(ydoc_ids, db_ids)
    new_ids = MapSet.difference(db_ids, ydoc_ids)
    existing_ids = MapSet.intersection(ydoc_ids, db_ids)

    delete_ops =
      phantom_ids
      |> Enum.map(&find_index_in_array(edges_array, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort(:desc)
      |> Enum.map(&{:delete, edges_array, &1})

    insert_ops =
      db_edges
      |> Enum.filter(&MapSet.member?(new_ids, &1.id))
      |> Enum.map(&{:insert, edges_array, edge_to_prelim(&1)})

    update_ops =
      db_edges
      |> Enum.filter(&MapSet.member?(existing_ids, &1.id))
      |> Enum.flat_map(fn db_edge ->
        ydoc_edge =
          Enum.find(ydoc_edges, &(Yex.Map.fetch!(&1, "id") == db_edge.id))

        edge_update_ops(ydoc_edge, db_edge)
      end)

    delete_ops ++ insert_ops ++ update_ops
  end

  defp edge_to_prelim(edge) do
    Yex.MapPrelim.from(%{
      "id" => edge.id,
      "condition_expression" => edge.condition_expression,
      "condition_label" => edge.condition_label,
      "condition_type" => to_string(edge.condition_type),
      "enabled" => edge.enabled,
      "source_job_id" => edge.source_job_id,
      "source_trigger_id" => edge.source_trigger_id,
      "target_job_id" => edge.target_job_id
    })
  end

  defp edge_update_ops(ydoc_edge, db_edge) do
    [
      {"condition_expression", db_edge.condition_expression},
      {"condition_label", db_edge.condition_label},
      {"condition_type", to_string(db_edge.condition_type)},
      {"enabled", db_edge.enabled},
      {"source_job_id", db_edge.source_job_id},
      {"source_trigger_id", db_edge.source_trigger_id},
      {"target_job_id", db_edge.target_job_id}
    ]
    |> Enum.flat_map(fn {key, db_val} ->
      case Yex.Map.fetch(ydoc_edge, key) do
        {:ok, ^db_val} -> []
        _ -> [{:set_field, ydoc_edge, key, db_val}]
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Trigger operations
  # ---------------------------------------------------------------------------

  defp compute_trigger_ops(triggers_array, ydoc_triggers, db_triggers) do
    ydoc_ids =
      ydoc_triggers |> Enum.map(&Yex.Map.fetch!(&1, "id")) |> MapSet.new()

    db_ids = db_triggers |> Enum.map(& &1.id) |> MapSet.new()

    phantom_ids = MapSet.difference(ydoc_ids, db_ids)
    new_ids = MapSet.difference(db_ids, ydoc_ids)
    existing_ids = MapSet.intersection(ydoc_ids, db_ids)

    delete_ops =
      phantom_ids
      |> Enum.map(&find_index_in_array(triggers_array, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort(:desc)
      |> Enum.map(&{:delete, triggers_array, &1})

    insert_ops =
      db_triggers
      |> Enum.filter(&MapSet.member?(new_ids, &1.id))
      |> Enum.map(&{:insert, triggers_array, trigger_to_prelim(&1)})

    update_ops =
      db_triggers
      |> Enum.filter(&MapSet.member?(existing_ids, &1.id))
      |> Enum.flat_map(fn db_trigger ->
        ydoc_trigger =
          Enum.find(ydoc_triggers, &(Yex.Map.fetch!(&1, "id") == db_trigger.id))

        trigger_update_ops(ydoc_trigger, db_trigger)
      end)

    delete_ops ++ insert_ops ++ update_ops
  end

  defp trigger_to_prelim(trigger) do
    kafka_configuration =
      trigger.kafka_configuration &&
        Yex.MapPrelim.from(%{
          "connect_timeout" => trigger.kafka_configuration.connect_timeout,
          "group_id" => trigger.kafka_configuration.group_id,
          "hosts_string" =>
            KafkaConfiguration.generate_hosts_string(
              trigger.kafka_configuration.hosts
            ),
          "initial_offset_reset_policy" =>
            trigger.kafka_configuration.initial_offset_reset_policy,
          "password" => trigger.kafka_configuration.password,
          "sasl" => to_string(trigger.kafka_configuration.sasl),
          "ssl" => trigger.kafka_configuration.ssl,
          "topics_string" =>
            KafkaConfiguration.generate_topics_string(
              trigger.kafka_configuration.topics
            ),
          "username" => trigger.kafka_configuration.username
        })

    Yex.MapPrelim.from(%{
      "id" => trigger.id,
      "type" => to_string(trigger.type),
      "enabled" => trigger.enabled,
      "cron_expression" => trigger.cron_expression,
      "cron_cursor_job_id" => trigger.cron_cursor_job_id,
      "webhook_reply" =>
        trigger.webhook_reply && to_string(trigger.webhook_reply),
      "kafka_configuration" => kafka_configuration
    })
  end

  defp trigger_update_ops(ydoc_trigger, db_trigger) do
    [
      {"type", to_string(db_trigger.type)},
      {"enabled", db_trigger.enabled},
      {"cron_expression", db_trigger.cron_expression},
      {"cron_cursor_job_id", db_trigger.cron_cursor_job_id},
      {"webhook_reply",
       db_trigger.webhook_reply && to_string(db_trigger.webhook_reply)}
    ]
    |> Enum.flat_map(fn {key, db_val} ->
      case Yex.Map.fetch(ydoc_trigger, key) do
        {:ok, ^db_val} -> []
        _ -> [{:set_field, ydoc_trigger, key, db_val}]
      end
    end)

    # kafka_configuration nested fields are not updated here — the provisioner
    # does not expose kafka config changes through this reconciliation path.
  end

  # ---------------------------------------------------------------------------
  # Apply reconcile operations
  # ---------------------------------------------------------------------------

  defp apply_reconcile_op({:insert, array, prelim}) do
    Yex.Array.push(array, prelim)
  end

  defp apply_reconcile_op({:delete, array, index}) do
    Yex.Array.delete(array, index)
  end

  defp apply_reconcile_op({:set_field, yex_map, key, value}) do
    Yex.Map.set(yex_map, key, value)
  end

  defp apply_reconcile_op({:update_text, text, new_content}) do
    len = Yex.Text.length(text)
    if len > 0, do: Yex.Text.delete(text, 0, len)
    Yex.Text.insert(text, 0, new_content)
  end

  # ---------------------------------------------------------------------------
  # Existing changeset-driven reconciler (unchanged below)
  # ---------------------------------------------------------------------------

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
