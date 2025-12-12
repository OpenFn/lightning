defmodule Lightning.Collaboration.PersistenceWriter do
  @moduledoc """
  A GenServer that accumulates Yjs document updates and batches them for
  efficient database writes.

  This process handles the batched persistence strategy using debouncing,
  size limits, and time limits to determine optimal flush timing. It monitors
  the SharedDoc process for proper cleanup and lifecycle management.

  The writer uses several strategies for efficient persistence:
  - Debouncing: Waits for activity to settle before saving
  - Batching: Combines multiple updates into a single database write
  - Checkpointing: Periodically consolidates updates for faster loading
  - Cleanup: Removes old updates after checkpoints
  """

  use GenServer

  import Ecto.Query

  alias Lightning.Collaboration.DocumentState
  alias Lightning.Collaboration.Registry
  alias Lightning.Repo

  require Logger

  # Configuration constants
  # Save after 2s of inactivity
  @debounce_ms 2_000
  # Max updates before forced save
  @max_batch_size 100
  # Force save after 30s
  @max_wait_ms 30_000
  # Create checkpoint after N updates
  @checkpoint_threshold 500
  # Clean old updates after 1 hour
  @cleanup_after_ms 3_600_000

  defstruct [
    :document_name,
    :save_timer,
    :max_wait_timer,
    :last_save_at,
    pending_updates: [],
    update_count: 0
  ]

  ## Client API

  @doc """
  Starts the PersistenceWriter GenServer for a specific document.

  Registers the process in the Registry with key {:persistence_writer, document_name}.
  """
  @spec start_link(opts :: Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, init_opts, name: name)
  end

  @doc """
  Adds a Yjs update to the pending batch for persistence.
  """
  def add_update(document_name, update) when is_binary(update) do
    if pid = Registry.whereis({:persistence_writer, document_name}) do
      GenServer.cast(pid, {:add_update, update})
      :ok
    else
      {:error, :not_found}
    end
  end

  @doc """
  Flushes all pending updates and stops the writer.

  This is called when the document is being unbound and ensures all
  updates are persisted before cleanup.
  """
  def flush_and_stop(document_name) do
    case Registry.lookup({:persistence_writer, document_name}) do
      [{pid, _}] ->
        GenServer.call(pid, :flush_and_stop, 10_000)

      [] ->
        :ok
    end
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    document_name = Keyword.fetch!(opts, :document_name)

    Logger.debug("Starting PersistenceWriter for document: #{document_name}")

    state = %__MODULE__{
      document_name: document_name,
      last_save_at: DateTime.utc_now()
    }

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_old_updates, @cleanup_after_ms)

    {:ok, state}
  end

  @impl true
  def handle_cast({:add_update, update}, state) do
    Logger.debug("Adding update to batch for document: #{state.document_name}")

    new_state = %{
      state
      | pending_updates: [update | state.pending_updates]
    }

    # Cancel existing timers
    new_state = cancel_timers(new_state)

    # Check if we should force save due to batch size
    if length(new_state.pending_updates) >= @max_batch_size do
      Logger.debug(
        "Batch size limit reached, forcing save for document: #{state.document_name}"
      )

      send(self(), :save_batch)
      {:noreply, new_state}
    else
      # Set debounce timer and max wait timer
      save_timer = Process.send_after(self(), :save_batch, @debounce_ms)

      max_wait_timer =
        if is_nil(state.max_wait_timer) do
          Process.send_after(self(), :force_save, @max_wait_ms)
        else
          state.max_wait_timer
        end

      new_state = %{
        new_state
        | save_timer: save_timer,
          max_wait_timer: max_wait_timer
      }

      {:noreply, new_state}
    end
  end

  @impl true
  def handle_call(:flush_and_stop, _from, state) do
    Logger.debug(
      "Flushing and stopping PersistenceWriter for document: #{state.document_name}"
    )

    # Cancel timers
    state = cancel_timers(state)

    # Save any pending updates
    case save_pending_updates(state) do
      {:ok, _} ->
        {:stop, :normal, :ok, state}

      {:error, reason} ->
        Logger.error(
          "Failed to flush updates for document #{state.document_name}: #{inspect(reason)}"
        )

        {:stop, :normal, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:save_batch, state) do
    Logger.debug("Saving batch for document: #{state.document_name}")

    state = cancel_timers(state)

    case save_pending_updates(state) do
      {:ok, update_count} ->
        new_state = %{
          state
          | pending_updates: [],
            last_save_at: DateTime.utc_now(),
            update_count: state.update_count + update_count
        }

        # Check if we need to create a checkpoint
        if new_state.update_count >= @checkpoint_threshold do
          send(self(), :create_checkpoint)
        end

        {:noreply, new_state}

      {:error, reason} ->
        Logger.error(
          "Failed to save batch for document #{state.document_name}: #{inspect(reason)}"
        )

        # Retry after a delay
        Process.send_after(self(), :save_batch, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:force_save, state) do
    Logger.debug("Force saving batch for document: #{state.document_name}")
    send(self(), :save_batch)
    {:noreply, %{state | max_wait_timer: nil}}
  end

  @impl true
  def handle_info(:create_checkpoint, state) do
    Logger.info("Creating checkpoint for document: #{state.document_name}")

    case create_checkpoint(state.document_name) do
      {:ok, _} ->
        Logger.info(
          "Checkpoint created successfully for document: #{state.document_name}"
        )

        new_state = %{state | update_count: 0}

        # Schedule cleanup of old updates
        Process.send_after(self(), :cleanup_old_updates, 5_000)

        {:noreply, new_state}

      {:error, reason} ->
        Logger.error(
          "Failed to create checkpoint for document #{state.document_name}: #{inspect(reason)}"
        )

        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:cleanup_old_updates, state) do
    Logger.info("Cleaning up old updates for document: #{state.document_name}")

    case cleanup_old_updates(state.document_name) do
      {:ok, deleted_count} ->
        if deleted_count > 0 do
          Logger.info(
            "Cleaned up #{deleted_count} old updates for document: #{state.document_name}"
          )
        end

      {:error, reason} ->
        Logger.error(
          "Failed to cleanup old updates for document #{state.document_name}: #{inspect(reason)}"
        )
    end

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_old_updates, @cleanup_after_ms)

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.debug(
      "SharedDoc process died for document #{state.document_name}: #{inspect(reason)}"
    )

    # Flush any pending updates before stopping
    state = cancel_timers(state)

    case save_pending_updates(state) do
      {:ok, _} ->
        Logger.debug(
          "Successfully flushed updates before stopping PersistenceWriter"
        )

      {:error, save_reason} ->
        Logger.debug(
          "Failed to flush updates before stopping: #{inspect(save_reason)}"
        )
    end

    {:stop, :normal, %{}}
  end

  @impl true
  def handle_info(any, state) do
    Logger.debug("PersistenceWriter received unknown message: #{inspect(any)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug(
      "#{inspect(self())} terminating for document #{state.document_name}: #{inspect(reason)}"
    )

    # Try to save any pending updates
    if length(state.pending_updates) > 0 do
      case save_pending_updates(state) do
        {:ok, _} ->
          Logger.debug("Successfully saved pending updates on termination")

        {:error, save_reason} ->
          Logger.debug(
            "Failed to save pending updates on termination: #{inspect(save_reason)}"
          )
      end
    end

    :ok
  end

  ## Private Functions

  defp cancel_timers(state) do
    if state.save_timer do
      Process.cancel_timer(state.save_timer)
    end

    if state.max_wait_timer do
      Process.cancel_timer(state.max_wait_timer)
    end

    %{state | save_timer: nil, max_wait_timer: nil}
  end

  defp save_pending_updates(%{pending_updates: []} = _state), do: {:ok, 0}

  defp save_pending_updates(state) do
    Logger.debug(
      "Saving #{length(state.pending_updates)} pending updates for document: #{state.document_name}"
    )

    # Merge multiple updates if we have more than one.
    # Pass document_name so merge_updates can load existing persisted state
    # before applying deltas (Yjs deltas require the base state to merge correctly).
    merged_update = merge_updates(state.pending_updates, state.document_name)

    document_state = %DocumentState{
      document_name: state.document_name,
      version: :update,
      state_data: merged_update
    }

    case Repo.insert(document_state) do
      {:ok, _inserted} ->
        {:ok, length(state.pending_updates)}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    exception ->
      Logger.error("Exception while saving updates: #{inspect(exception)}")
      {:error, exception}
  end

  defp merge_updates([update], _document_name), do: update

  defp merge_updates(updates, document_name) when length(updates) > 1 do
    # Load the current persisted state first, then apply the new deltas.
    # This is necessary because Yjs delta updates only contain changes,
    # not the full state. Without the base state, applying deltas to an
    # empty document produces an empty result.
    temp_doc = Yex.Doc.new()

    # Load existing persisted state (checkpoint + any previously saved updates)
    DocumentState.load_into_doc(temp_doc, document_name)

    # Apply new updates in chronological order (oldest first)
    updates
    |> Enum.reverse()
    |> Enum.each(fn update ->
      Yex.apply_update(temp_doc, update)
    end)

    Yex.encode_state_as_update!(temp_doc)
  rescue
    exception ->
      Logger.error("Failed to merge updates: #{inspect(exception)}")
      # Fallback to the most recent update
      hd(updates)
  end

  defp create_checkpoint(document_name) do
    # Get the latest checkpoint (if any) and all updates since then
    latest_checkpoint =
      Repo.one(
        from d in DocumentState,
          where:
            d.document_name == ^document_name and d.version == ^"checkpoint",
          order_by: [desc: d.inserted_at],
          limit: 1
      )

    checkpoint_time =
      if latest_checkpoint,
        do: latest_checkpoint.inserted_at,
        else: ~U[1970-01-01 00:00:00Z]

    updates =
      Repo.all(
        from d in DocumentState,
          where:
            d.document_name == ^document_name and
              d.version == ^"update" and
              d.inserted_at > ^checkpoint_time,
          order_by: [asc: d.inserted_at]
      )

    if length(updates) > 0 do
      # Reconstruct the document state
      temp_doc = Yex.Doc.new()

      # Apply checkpoint first if it exists
      if latest_checkpoint do
        Yex.apply_update(temp_doc, latest_checkpoint.state_data)
      end

      # Apply all updates in order
      Enum.each(updates, fn update_record ->
        Yex.apply_update(temp_doc, update_record.state_data)
      end)

      # Create new checkpoint
      checkpoint_data = Yex.encode_state_as_update!(temp_doc)

      checkpoint = %DocumentState{
        document_name: document_name,
        version: :checkpoint,
        state_data: checkpoint_data
      }

      Repo.insert(checkpoint)
    else
      {:ok, nil}
    end
  rescue
    exception ->
      Logger.error("Exception while creating checkpoint: #{inspect(exception)}")
      {:error, exception}
  end

  defp cleanup_old_updates(document_name) do
    # Find the latest checkpoint
    latest_checkpoint =
      Repo.one(
        from d in DocumentState,
          where:
            d.document_name == ^document_name and d.version == ^"checkpoint",
          order_by: [desc: d.inserted_at],
          limit: 1
      )

    if latest_checkpoint do
      # Delete updates that are older than the checkpoint and older than 1 hour
      cutoff_time =
        DateTime.add(DateTime.utc_now(), -@cleanup_after_ms, :millisecond)

      {deleted_count, _} =
        Repo.delete_all(
          from d in DocumentState,
            where:
              d.document_name == ^document_name and
                d.version == ^"update" and
                d.inserted_at < ^latest_checkpoint.inserted_at and
                d.inserted_at < ^cutoff_time
        )

      {:ok, deleted_count}
    else
      {:ok, 0}
    end
  rescue
    exception ->
      Logger.error(
        "Exception while cleaning up old updates: #{inspect(exception)}"
      )

      {:error, exception}
  end
end
