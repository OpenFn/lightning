defmodule WorkflowLive.WorkFlowNameValidator do
  alias Lightning.Workflows
  alias Lightning.Workflows.Workflow
  defstruct [:name, :project_id]
  @types %{name: :string, project_id: :string}
  import Ecto.Changeset

  def changeset(%__MODULE__{} = workflow, attrs) do
    {workflow, @types}
    |> cast(attrs, Map.keys(@types))
    |> validate_required([:name])
    |> validate()
  end

  def validate(changeset) do
    workflow_name = get_field(changeset, :name)
    project_id = get_field(changeset, :project_id)

    if workflow_name && project_id do
      case Workflows.workflow_exists?(project_id, workflow_name) do
        true ->
          add_error(changeset, :name, "Workflow name already been used")

        false ->
          changeset
      end
    else
      changeset
    end
  end

  def validate_workflow(%__MODULE__{} = workflow, attrs \\ %{}) do
    changeset(workflow, attrs)
  end
end
