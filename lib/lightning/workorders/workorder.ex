defmodule Lightning.WorkOrder do
  @moduledoc """
  Ecto model for WorkOrders.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Lightning.Invocation.Dataclip
  alias Lightning.Run
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow

  require Run

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          state: atom(),
          dataclip: Dataclip.t() | Ecto.Association.NotLoaded.t(),
          snapshot: Snapshot.t() | Ecto.Association.NotLoaded.t(),
          trigger: Trigger.t() | Ecto.Association.NotLoaded.t(),
          workflow: Workflow.t() | Ecto.Association.NotLoaded.t()
        }

  @state_values Enum.concat(
                  [:rejected, :pending, :running],
                  Run.final_states()
                )

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "work_orders" do
    field :state, Ecto.Enum,
      values: @state_values,
      default: :pending

    field :last_activity, :utc_datetime_usec,
      autogenerate: {DateTime, :utc_now, []}

    belongs_to :workflow, Workflow
    belongs_to :snapshot, Snapshot

    belongs_to :trigger, Trigger
    belongs_to :dataclip, Dataclip

    has_many :runs, Run, preload_order: [desc: :inserted_at]
    has_many :jobs, through: [:workflow, :jobs]

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(workorder, attrs) do
    workorder
    |> cast(attrs, [:state, :last_activity, :workflow_id])
    |> validate_required([:state, :last_activity, :workflow_id])
    |> validate()
  end

  def validate(changeset) do
    changeset
    |> assoc_constraint(:workflow)
    |> assoc_constraint(:snapshot)
  end
end
