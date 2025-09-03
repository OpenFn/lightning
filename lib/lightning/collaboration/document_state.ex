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
end
