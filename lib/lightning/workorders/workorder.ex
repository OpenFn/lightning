defmodule Lightning.WorkOrder do
  @moduledoc """
  Ecto model for Workorders.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Lightning.Workflows.{Workflow, Trigger}
  alias Lightning.Invocation.Dataclip
  alias Lightning.{InvocationReason, Attempt}

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          trigger: Trigger.t() | Ecto.Association.NotLoaded.t(),
          dataclip: Dataclip.t() | Ecto.Association.NotLoaded.t(),
          workflow: Workflow.t() | Ecto.Association.NotLoaded.t(),
          reason: InvocationReason.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "work_orders" do
    field :state, Ecto.Enum,
      values: [:pending, :running, :success, :failed, :killed, :crashed],
      default: :pending

    belongs_to :workflow, Workflow

    belongs_to :trigger, Trigger
    belongs_to :dataclip, Dataclip

    belongs_to :reason, InvocationReason
    has_many :attempts, Attempt
    has_many :jobs, through: [:workflow, :jobs]

    timestamps(type: :utc_datetime_usec)
  end

  def new() do
    change(%__MODULE__{}, %{id: Ecto.UUID.generate()})
    |> validate()
  end

  @doc false
  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:state, :reason_id, :workflow_id])
    |> validate_required([:state, :reason_id, :workflow_id])
    |> validate()
  end

  def validate(changeset) do
    changeset
    |> assoc_constraint(:workflow)
  end
end
