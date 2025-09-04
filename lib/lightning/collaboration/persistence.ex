defmodule Lightning.Collaboration.Persistence do
  @moduledoc """
  Persistence implementation for collaborative workflow documents.

  Stores Y.js document updates in the database and provides
  efficient loading and saving of document state.
  """

  @behaviour Yex.Sync.SharedDoc.PersistenceBehaviour

  use Lightning.Utils.Logger, color: [:blue_background]

  alias Lightning.Collaboration.DocumentState
  alias Lightning.Collaboration.PersistenceWriter
  alias Lightning.Collaboration.Session
  alias Lightning.Repo

  @impl true
  def bind(state, doc_name, doc) do
    workflow_id = Map.get(state, :workflow_id)

    if !workflow_id do
      raise KeyError, """
      workflow_id is required in state: #{inspect(state)}

      Ensure you are starting the SharedDoc with the correct persistence opts.
      """
    end

    case load_document_records(doc_name) do
      {:ok, checkpoint, updates} ->
        # Apply checkpoint first if exists
        if checkpoint do
          info("Applying checkpoint to document. document=#{doc_name}")
          Yex.apply_update(doc, checkpoint.state_data)
        end

        # Then apply updates in chronological order
        Enum.each(updates, fn update ->
          Yex.apply_update(doc, update.state_data)
        end)

        info("Loaded #{length(updates)} updates. document=#{doc_name}")

      {:error, :not_found} ->
        info("No persisted state found, starting fresh. document=#{doc_name}")

        Session.initialize_workflow_document(doc, workflow_id)

        :ok
    end

    # Return state for tracking
    state |> Map.put(:last_save, DateTime.utc_now(:microsecond))
  end

  @impl true
  def update_v1(state, update, doc_name, _doc) do
    # Send to PersistenceWriter via state
    case PersistenceWriter.add_update(doc_name, update) do
      :ok ->
        state

      {:error, reason} ->
        error("Failed to add update to PersistenceWriter: #{inspect(reason)}")
        state
    end
  end

  @impl true
  def unbind(state, doc_name, _doc) do
    info("SharedDoc shutting down, flushing persistence. document=#{doc_name}")

    if writer = state[:persistence_writer] do
      # Synchronously flush and stop the writer
      try do
        GenServer.call(writer, :flush_and_stop, 10_000)
      catch
        :exit, _ ->
          error(
            "PersistenceWriter unavailable during unbind. document=#{doc_name}"
          )
      end
    end

    :ok
  end

  # Private functions
  defp load_document_records(doc_name) do
    import Ecto.Query

    # Get latest checkpoint
    checkpoint =
      Repo.one(
        from d in DocumentState,
          where: d.document_name == ^doc_name and d.version == :checkpoint,
          order_by: [desc: d.inserted_at],
          limit: 1
      )

    checkpoint_time =
      if checkpoint, do: checkpoint.inserted_at, else: ~U[1970-01-01 00:00:00Z]

    # Get updates after checkpoint
    updates =
      Repo.all(
        from d in DocumentState,
          where:
            d.document_name == ^doc_name and
              d.version == :update and
              d.inserted_at > ^checkpoint_time,
          order_by: [asc: d.inserted_at]
      )

    if checkpoint || length(updates) > 0 do
      {:ok, checkpoint, updates}
    else
      {:error, :not_found}
    end
  end
end
