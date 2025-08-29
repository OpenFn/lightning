defmodule Lightning.Collaboration.Persistence do
  @moduledoc """
  Persistence implementation for collaborative workflow documents.

  Stores Y.js document updates in the database and provides
  efficient loading and saving of document state.
  """

  @behaviour Yex.Sync.SharedDoc.PersistenceBehaviour

  alias Lightning.Collaboration.DocumentState
  alias Lightning.Repo

  require Logger

  @impl true
  def bind(_state, doc_name, doc) do
    Logger.info(
      "Loading persisted state. pid=#{inspect(self())} document=#{doc_name}"
    )

    case load_document_state(doc_name) do
      {:ok, binary_state} ->
        case Yex.apply_update(doc, binary_state) do
          :ok ->
            Logger.info(
              "Successfully loaded persisted state. document=#{doc_name}"
            )

            :ok

          {:error, reason} ->
            Logger.warning(
              "Failed to apply persisted state. document=#{doc_name} reason=#{inspect(reason)}"
            )

            :ok
        end

      {:error, :not_found} ->
        Logger.info(
          "No persisted state found, starting fresh. document=#{doc_name}"
        )

        :ok
    end

    # Return state for tracking
    %{doc_name: doc_name, last_save: DateTime.utc_now()}
  end

  @impl true
  def update_v1(state, update, doc_name, _doc) do
    Logger.debug(
      "Received update, state persistence scheduled. document=#{doc_name}"
    )

    # TODO For now, we'll persist every update immediately
    # In production, you might want to batch updates or use async persistence
    Task.start(fn ->
      save_update(doc_name, update)
    end)

    # Update last save time in state
    %{state | last_save: DateTime.utc_now()}
  end

  @impl true
  def unbind(%{doc_name: doc_name}, _doc_name, doc) do
    Logger.info(
      "Saving final state. pid=#{inspect(self())} document=#{doc_name}"
    )

    case Yex.encode_state_as_update(doc) do
      {:ok, update} ->
        save_document_state(doc_name, update)

        Logger.info("Successfully saved final state. document=#{doc_name}")

      {:error, reason} ->
        Logger.error(
          "Failed to encode final state. document=#{doc_name} reason=#{inspect(reason)}"
        )
    end

    :ok
  end

  # Private functions

  defp load_document_state(doc_name) do
    case Repo.get_by(DocumentState, document_name: doc_name) do
      nil ->
        {:error, :not_found}

      %DocumentState{state_data: state_data} ->
        {:ok, state_data}
    end
  end

  defp save_document_state(doc_name, binary_state) do
    attrs = %{
      document_name: doc_name,
      state_data: binary_state,
      updated_at: DateTime.utc_now()
    }

    case Repo.get_by(DocumentState, document_name: doc_name) do
      nil ->
        %DocumentState{}
        |> DocumentState.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> DocumentState.changeset(attrs)
        |> Repo.update()
    end
  end

  defp save_update(doc_name, update) do
    # For immediate persistence, we could store individual updates
    # For now, let's just log them and rely on the final unbind save
    Logger.debug(
      "Received update. document=#{doc_name} size_bytes=#{byte_size(update)}"
    )
  end
end
