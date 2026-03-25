defmodule Lightning.Collaboration.DocumentState do
  @moduledoc """
  Schema for persisting Y.js collaborative document states.

  Supports multiple record types for batched persistence:
  - "update": Individual or batched updates
  - "checkpoint": Full document state snapshot
  - "state_vector": Current state vector for efficient syncing
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Lightning.Repo

  @type t :: %__MODULE__{
          id: integer() | nil,
          document_name: String.t() | nil,
          state_data: binary() | nil,
          state_vector: binary() | nil,
          version: :update | :checkpoint | :state_vector | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "collaboration_document_states" do
    field :document_name, :string
    field :state_data, :binary
    field :state_vector, :binary
    field :version, Ecto.Enum, values: [:update, :checkpoint, :state_vector]

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(document_state, attrs) do
    document_state
    |> cast(attrs, [
      :document_name,
      :state_data,
      :state_vector,
      :version
    ])
    |> validate_required([:document_name, :state_data, :version])
  end

  @doc """
  Retrieves the latest checkpoint and all updates since that checkpoint
  for a given document.

  Returns `{:ok, checkpoint, updates}` where checkpoint may be nil,
  or `{:error, :not_found}` if no persisted state exists.
  """
  @spec get_checkpoint_and_updates(String.t()) ::
          {:ok, __MODULE__.t() | nil, [__MODULE__.t()]} | {:error, :not_found}
  def get_checkpoint_and_updates(doc_name) do
    checkpoint = get_latest_checkpoint(doc_name)

    checkpoint_time =
      if checkpoint, do: checkpoint.inserted_at, else: ~U[1970-01-01 00:00:00Z]

    updates = get_updates_since(doc_name, checkpoint_time)

    if checkpoint || length(updates) > 0 do
      {:ok, checkpoint, updates}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Retrieves the latest checkpoint for a document, or nil if none exists.
  """
  @spec get_latest_checkpoint(String.t()) :: __MODULE__.t() | nil
  def get_latest_checkpoint(doc_name) do
    Repo.one(
      from d in __MODULE__,
        where: d.document_name == ^doc_name and d.version == :checkpoint,
        order_by: [desc: d.inserted_at],
        limit: 1
    )
  end

  @doc """
  Retrieves all updates for a document inserted after the given timestamp,
  ordered chronologically (oldest first).
  """
  @spec get_updates_since(String.t(), DateTime.t()) :: [__MODULE__.t()]
  def get_updates_since(doc_name, since) do
    Repo.all(
      from d in __MODULE__,
        where:
          d.document_name == ^doc_name and
            d.version == :update and
            d.inserted_at > ^since,
        order_by: [asc: d.inserted_at]
    )
  end

  @doc """
  Applies persisted state (checkpoint + updates) to a Yex document.

  Applies the checkpoint first (if present), then all updates in
  chronological order.
  """
  @spec apply_to_doc(Yex.Doc.t(), __MODULE__.t() | nil, [__MODULE__.t()]) :: :ok
  def apply_to_doc(doc, checkpoint, updates) do
    if checkpoint do
      Yex.apply_update(doc, checkpoint.state_data)
    end

    Enum.each(updates, fn update ->
      Yex.apply_update(doc, update.state_data)
    end)

    :ok
  end

  @doc """
  Loads all persisted state for a document and applies it to a Yex document.

  Convenience function that combines `get_checkpoint_and_updates/1` and
  `apply_to_doc/3`.
  """
  @spec load_into_doc(Yex.Doc.t(), String.t()) :: :ok
  def load_into_doc(doc, doc_name) do
    checkpoint = get_latest_checkpoint(doc_name)

    checkpoint_time =
      if checkpoint, do: checkpoint.inserted_at, else: ~U[1970-01-01 00:00:00Z]

    updates = get_updates_since(doc_name, checkpoint_time)
    apply_to_doc(doc, checkpoint, updates)
  end
end
