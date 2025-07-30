defmodule Lightning.WorkflowCollaboration.DocumentState do
  @moduledoc """
  Schema for persisting Y.js collaborative document states.

  Stores the binary-encoded CRDT state for workflow documents
  to enable persistence across server restarts.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "workflow_document_states" do
    field :document_name, :string
    field :state_data, :binary
    # For efficient updates in the future
    field :state_vector, :binary
    field :user_count, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(document_state, attrs) do
    document_state
    |> cast(attrs, [
      :document_name,
      :state_data,
      :state_vector,
      :user_count
    ])
    |> validate_required([:document_name, :state_data])
    |> unique_constraint(:document_name)
  end
end
