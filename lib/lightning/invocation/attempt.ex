defmodule Lightning.Attempt do
  @moduledoc """
  Ecto model for Attempts.


  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Lightning.InvocationReason
  alias Lightning.WorkOrder
  alias Lightning.Invocation.Run

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          reason: InvocationReason.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "attempts" do
    belongs_to :workorder, WorkOrder
    belongs_to :reason, InvocationReason
    many_to_many :runs, Run, join_through: "attempt_runs"

    timestamps()
  end

  @doc false
  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:reason_id, :workorder_id])
    |> cast_assoc(:runs, required: false)
    |> validate_required([:reason_id, :workorder_id])
    |> assoc_constraint(:workorder)
    |> assoc_constraint(:reason)
  end
end
