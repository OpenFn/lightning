defmodule Lightning.WorkOrder do
  @moduledoc """
  Ecto model for Workorders.


  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Lightning.InvocationReason
  alias Lightning.Invocation.Run

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          workflow: Workflow.t() | Ecto.Association.NotLoaded.t(),
          reason: InvocationReason.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "workorders" do
    belongs_to :workflow, Workflow
    belongs_to :reason, InvocationReason

    timestamps()
  end

  @doc false
  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:reason_id, :workflow_id])
    |> validate_required([:reason_id, :workflow_id])
    |> assoc_constraint(:workflow)
    |> assoc_constraint(:reason)
  end
end
