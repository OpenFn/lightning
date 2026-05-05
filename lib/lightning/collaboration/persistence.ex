defmodule Lightning.Collaboration.Persistence do
  @moduledoc """
  Persistence implementation for collaborative workflow documents.

  Stores Y.js document updates in the database and provides
  efficient loading and saving of document state.
  """

  @behaviour Yex.Sync.SharedDoc.PersistenceBehaviour

  alias Lightning.Collaboration.DocumentState
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
    case state[:persistence_writer] do
      nil ->
        Logger.error(
          "PersistenceWriter pid not in persistence state. document=#{doc_name}"
        )

        state

      pid ->
        GenServer.cast(pid, {:add_update, update})
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
end
