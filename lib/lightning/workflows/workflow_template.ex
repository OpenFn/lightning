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
    field :positions, :string
    field :tags, {:array, :string}, default: []

    belongs_to :workflow, Workflow

    timestamps()
  end

  @doc false
  def changeset(template, attrs) do
    template
    |> cast(attrs, [:name, :description, :code, :positions, :tags, :workflow_id])
    |> validate_required([:name, :code, :tags, :workflow_id])
    |> validate_length(:name,
      max: 255,
      message: "Name must be less than 255 characters"
    )
    |> validate_length(:description,
      max: 1000,
      message: "Description must be less than 1000 characters"
    )
    |> assoc_constraint(:workflow)
  end
end
