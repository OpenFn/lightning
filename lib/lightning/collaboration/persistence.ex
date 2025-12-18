defmodule Lightning.Collaboration.Persistence do
  @moduledoc """
  Persistence implementation for collaborative workflow documents.

  Stores Y.js document updates in the database and provides
  efficient loading and saving of document state.
  """

  @behaviour Yex.Sync.SharedDoc.PersistenceBehaviour

  alias Lightning.Collaboration.DocumentState
  alias Lightning.Collaboration.PersistenceWriter
  alias Lightning.Collaboration.Session

  require Logger

  @impl true
  def bind(state, doc_name, doc) do
    workflow = Map.fetch!(state, :workflow)

    if !workflow do
      raise KeyError, """
      workflow is required in state: #{inspect(state)}

      Ensure you are starting the SharedDoc with the correct persistence opts.
      """
    end

    case DocumentState.get_checkpoint_and_updates(doc_name) do
      {:ok, checkpoint, updates} ->
        apply_persisted_state(doc, doc_name, checkpoint, updates)
        reconcile_or_reset(doc, doc_name, workflow)

      {:error, :not_found} ->
        Logger.info(
          "No persisted state found, starting fresh. document=#{doc_name}"
        )

        Session.initialize_workflow_document(doc, workflow)
    end

    # Return state for tracking
    state |> Map.put(:last_save, DateTime.utc_now(:microsecond))
  end

  @impl true
  def update_v1(state, update, doc_name, _doc) do
    case PersistenceWriter.add_update(doc_name, update) do
      :ok ->
        state

      {:error, reason} ->
        Logger.error(
          "Failed to add update to PersistenceWriter: #{inspect(reason)}"
        )

        state
    end
  end

  @impl true
  def unbind(state, doc_name, _doc) do
    Logger.debug(
      "SharedDoc shutting down, flushing persistence. document=#{doc_name}"
    )

    if writer = state[:persistence_writer] do
      # Synchronously flush and stop the writer
      try do
        GenServer.call(writer, :flush_and_stop, 10_000)
      catch
        :exit, _ ->
          Logger.error(
            "PersistenceWriter unavailable during unbind. document=#{doc_name}"
          )
      end
    end

    :ok
  end

  # Private functions
  defp apply_persisted_state(doc, doc_name, checkpoint, updates) do
    if checkpoint do
      Logger.info("Applying checkpoint to document. document=#{doc_name}")
    end

    DocumentState.apply_to_doc(doc, checkpoint, updates)
    Logger.debug("Loaded #{length(updates)} updates. document=#{doc_name}")
  end

  defp reconcile_or_reset(doc, doc_name, workflow) do
    workflow_map = Yex.Doc.get_map(doc, "workflow")
    persisted_lock_version = extract_lock_version(workflow_map)
    current_lock_version = workflow.lock_version

    if stale?(persisted_lock_version, current_lock_version) do
      Logger.warning("""
      Persisted Y.Doc is stale (persisted: #{inspect(persisted_lock_version)}, \
      current: #{current_lock_version})
      Discarding persisted state and reloading from database.
      document=#{doc_name}
      """)

      clear_and_reset_workflow(doc, workflow)
    else
      Logger.debug(
        "Persisted Y.Doc is current (lock_version: #{current_lock_version}). document=#{doc_name}"
      )

      reconcile_workflow_metadata(doc, workflow)
    end
  end

  defp extract_lock_version(workflow_map) do
    case Yex.Map.fetch(workflow_map, "lock_version") do
      {:ok, version} when is_float(version) -> trunc(version)
      {:ok, version} when is_integer(version) -> version
      {:ok, nil} -> nil
      :error -> nil
    end
  end

  defp stale?(nil, current_version), do: not is_nil(current_version)

  defp stale?(persisted_version, current_version),
    do: persisted_version != current_version

  defp clear_and_reset_workflow(doc, workflow) do
    # Same pattern as Session.clear_and_reset_doc
    # Get all Yex collections BEFORE transaction to avoid VM deadlock
    jobs_array = Yex.Doc.get_array(doc, "jobs")
    edges_array = Yex.Doc.get_array(doc, "edges")
    triggers_array = Yex.Doc.get_array(doc, "triggers")

    # Transaction 1: Clear all arrays
    Yex.Doc.transaction(doc, "clear_stale_workflow", fn ->
      clear_array(jobs_array)
      clear_array(edges_array)
      clear_array(triggers_array)
    end)

    # Transaction 2: Re-serialize workflow from database
    Session.initialize_workflow_document(doc, workflow)

    :ok
  end

  defp clear_array(array) do
    length = Yex.Array.length(array)

    if length > 0 do
      Yex.Array.delete_range(array, 0, length)
    end
  end

  defp reconcile_workflow_metadata(doc, workflow) do
    # Update workflow metadata fields to match current database state
    # This is critical when loading persisted Y.Doc state that may be stale
    workflow_map = Yex.Doc.get_map(doc, "workflow")

    Yex.Doc.transaction(doc, "reconcile_metadata", fn ->
      # Update lock_version to current database value
      Yex.Map.set(workflow_map, "lock_version", workflow.lock_version)

      # Update name in case it changed
      Yex.Map.set(workflow_map, "name", workflow.name)

      # Update deleted_at if present
      # Convert DateTime to string for Yex compatibility (Yex doesn't support DateTime structs)
      Yex.Map.set(
        workflow_map,
        "deleted_at",
        workflow.deleted_at && to_string(workflow.deleted_at)
      )
    end)

    Logger.debug(
      "Reconciled workflow metadata: lock_version=#{workflow.lock_version}, name=#{workflow.name}"
    )

    :ok
  end
end
