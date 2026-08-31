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
    field :positions, :map
    field :tags, {:array, :string}, default: []

    belongs_to :workflow, Workflow

    timestamps()
  end

  @doc false
  def changeset(template, attrs) do
    template
    |> cast(attrs, [:name, :description, :code, :positions, :tags, :workflow_id])
    |> validate_required([:name, :code, :tags, :workflow_id])
    |> Lightning.Validators.validate_name(
      :name,
      "Name can't contain control characters"
    )
    |> validate_length(:name,
      max: 255,
      message: "Name must be less than 255 characters"
    )
    |> Lightning.Validators.validate_name_fits_column(
      :name,
      "Name is too long, please use a shorter one"
    )
    |> validate_length(:description,
      max: 1000,
      message: "Description must be less than 1000 characters"
    )
    # positions is jsonb and code, description and tags are text columns, all
    # copied into the snapshot. publish_template exposes every one (#4893).
    |> Lightning.Validators.validate_no_null_bytes_deep(
      :positions,
      "Positions can't contain a null byte"
    )
    |> Lightning.Validators.validate_no_null_bytes(
      :code,
      "Code can't contain a null byte"
    )
    |> Lightning.Validators.validate_no_null_bytes(
      :description,
      "Description can't contain a null byte"
    )
    |> Lightning.Validators.validate_no_null_bytes_deep(
      :tags,
      "Tags can't contain a null byte"
    )
    |> assoc_constraint(:workflow)
  end
end
