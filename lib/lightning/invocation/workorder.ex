defmodule Lightning.WorkOrder do
  @moduledoc """
  Ecto model for Workorders.


  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Lightning.Workflows.Workflow
  alias Lightning.{InvocationReason, Attempt}

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          workflow: Workflow.t() | Ecto.Association.NotLoaded.t(),
          reason: InvocationReason.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "work_orders" do
    belongs_to :workflow, Workflow
    belongs_to :reason, InvocationReason
    has_many :attempts, Attempt

    timestamps()
  end

  def new() do
    change(%__MODULE__{}, %{id: Ecto.UUID.generate()})
    |> validate()
  end

  @doc false
  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:reason_id, :workflow_id])
    |> validate_required([:reason_id, :workflow_id])
    |> validate()
  end

  defp validate(changeset) do
    changeset
    |> assoc_constraint(:workflow)
    |> assoc_constraint(:reason)
  end
end
