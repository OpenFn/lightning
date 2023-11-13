defmodule LightningWeb.WorkflowLive.NewWorkflowForm do
  import Ecto.Changeset

  alias Lightning.Workflows

  @types %{name: :string, project_id: Ecto.UUID}

  def validate(attrs, project_id) do
    {%{}, @types}
    |> cast(attrs, Map.keys(@types))
    |> put_change(:project_id, project_id)
    |> validate_required([:name, :project_id])
  end

  def validate_for_save(changeset) do
    changeset
    |> validate_unique_name()
  end

  defp validate_unique_name(changeset) do
    project_id = get_field(changeset, :project_id)

    if changeset.valid? do
      changeset
    else
      changeset
      |> validate_change(:name, fn :name, name ->
        if Workflows.workflow_exists?(project_id, name) do
          [name: "Workflow name already used"]
        else
          []
        end
      end)
    end
  end
end
