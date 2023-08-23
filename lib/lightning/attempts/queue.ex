defmodule Lightning.Attempts.Queue do
  use Ecto.Schema
  import Ecto.Changeset

  @foreign_key_type :binary_id
  schema "attempts_queue" do
    belongs_to :attempt, Lightning.Attempt

    field :state, :string, default: "available"

    field :claimed_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec

    timestamps type: :utc_datetime_usec, updated_at: false
  end

  def new(%Lightning.Attempt{} = attempt) do
    %__MODULE__{}
    |> change()
    |> put_assoc(:attempt, attempt)
    |> assoc_constraint(:attempt)
  end
end
