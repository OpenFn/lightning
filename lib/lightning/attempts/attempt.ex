defmodule Lightning.Attempt do
  @moduledoc """
  Ecto model for Attempts.


  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Lightning.InvocationReason
  alias Lightning.WorkOrder
  alias Lightning.Invocation.Run
  alias Lightning.AttemptRun

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          reason: InvocationReason.t() | Ecto.Association.NotLoaded.t(),
          work_order: WorkOrder.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "attempts" do
    belongs_to :work_order, WorkOrder
    belongs_to :reason, InvocationReason
    many_to_many :runs, Run, join_through: AttemptRun

    field :state, :string, default: "available"

    field :claimed_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec

    timestamps type: :utc_datetime_usec, updated_at: false
  end

  def new(attrs \\ %{}) do
    change(%__MODULE__{}, %{id: Ecto.UUID.generate()})
    |> change(attrs)
    |> validate()
  end

  @doc false
  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:reason_id, :work_order_id])
    |> cast_assoc(:runs, required: false)
    |> validate_required([:reason_id, :work_order_id])
    |> validate()
  end

  defp validate(changeset) do
    changeset
    |> assoc_constraint(:work_order)
    |> assoc_constraint(:reason)
  end
end
