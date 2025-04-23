defmodule Lightning.Workflows.WorkflowTemplate do
  @moduledoc """
  Schema for workflow templates.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Workflows.Workflow

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "workflow_templates" do
    field :name, :string
    field :description, :string
    field :code, :string
    field :layout, :string
    field :tags, {:array, :string}, default: []

    belongs_to :workflow, Workflow

    timestamps()
  end

  @doc false
  def changeset(template, attrs) do
    template
    |> cast(attrs, [:name, :description, :code, :layout, :tags, :workflow_id])
    |> validate_required([:name, :code, :tags, :workflow_id])
    |> assoc_constraint(:workflow)
  end
end
