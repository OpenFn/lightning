defmodule Lightning.Projects.Provisioner do
  @moduledoc """
  Provides functions for importing projects. This module is used by the
  provisioning HTTP API.

  When providing a project to import, all records must have an `id` field.
  It's up to the caller to ensure that the `id` is unique and generated
  ahead of time in the case of new records.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias Lightning.Projects.Project
  alias Lightning.Jobs.{Job, Trigger}
  alias Lightning.Workflows.{Workflow, Edge}
  alias Lightning.Repo

  @doc """
  Import a project.
  """
  @spec import_document(Project.t() | nil, map()) ::
          {:error, Ecto.Changeset.t(Project.t())}
          | {:ok, Project.t()}
  def import_document(nil, data), do: import_document(%Project{}, data)

  def import_document(project, data) do
    project
    |> maybe_reload_project()
    |> parse_document(data)
    |> Repo.insert_or_update()
    |> case do
      {:ok, %{id: id}} ->
        {:ok, load_project(id)}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @spec parse_document(Project.t(), map()) :: Ecto.Changeset.t(Project.t())
  def parse_document(%Project{} = project, data) when is_map(data) do
    project
    |> Project.changeset_for_import(data)
    |> cast_assoc(:workflows, with: &workflow_changeset/2)
    |> validate_required([:id])
  end

  @spec load_project(Ecto.UUID.t()) :: Project.t() | nil
  def load_project(id) do
    from(p in Project,
      where: p.id == ^id,
      preload: [workflows: [:jobs, :triggers, :edges]]
    )
    |> Repo.one()
  end

  defp maybe_reload_project(project) do
    if project.id do
      load_project(project.id)
    else
      project
    end
  end

  defp workflow_changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [:id, :name, :delete])
    |> validate_required([:id])
    |> maybe_mark_for_deletion()
    |> cast_assoc(:jobs, with: &job_changeset/2)
    |> cast_assoc(:triggers, with: &trigger_changeset/2)
    |> cast_assoc(:edges, with: &edge_changeset/2)
    |> Workflow.validate()
  end

  defp job_changeset(job, attrs) do
    job
    |> cast(attrs, [:id, :name, :body, :enabled, :adaptor, :delete])
    |> validate_required([:id])
    |> Job.validate()
    |> validate_extraneous_params()
    |> maybe_mark_for_deletion()
    |> maybe_ignore()
  end

  defp trigger_changeset(trigger, attrs) do
    trigger
    |> cast(attrs, [
      :id,
      :comment,
      :custom_path,
      :type,
      :cron_expression,
      :delete
    ])
    |> validate_required([:id])
    |> Trigger.validate()
    |> validate_extraneous_params()
    |> maybe_mark_for_deletion()
    |> maybe_ignore()
  end

  defp edge_changeset(edge, attrs) do
    edge
    |> cast(attrs, [
      :id,
      :source_job_id,
      :source_trigger_id,
      :condition,
      :target_job_id,
      :delete
    ])
    |> validate_required([:id])
    |> Edge.validate()
    |> validate_extraneous_params()
    |> maybe_mark_for_deletion()
    |> maybe_ignore()
  end

  defp maybe_ignore(changeset) do
    changeset
    |> case do
      %{valid?: true, changes: changes} = changeset when changes == %{} ->
        %{changeset | action: :ignore}

      changeset ->
        changeset
    end
  end

  defp maybe_mark_for_deletion(changeset) do
    changeset.changes
    |> Map.pop(:delete)
    |> case do
      {true, others} when map_size(others) == 0 ->
        %{changeset | action: :delete}

      {true, others} when map_size(others) > 0 ->
        changeset
        |> add_error(:delete, "cannot change or add a record while deleting")

      _ ->
        changeset
    end
  end

  @doc """
  Validate that there are no extraneous parameters in the changeset.

  For all params in the changeset, ensure that the param is in the list of
  known fields in the schema.
  """
  def validate_extraneous_params(changeset) do
    param_keys = changeset.params |> Map.keys() |> MapSet.new(&to_string/1)
    field_keys = changeset.types |> Map.keys() |> MapSet.new(&to_string/1)

    extraneous_params = MapSet.difference(param_keys, field_keys)

    if MapSet.size(extraneous_params) > 0 do
      add_error(changeset, :base, "extraneous parameters: %{params}",
        params: MapSet.to_list(extraneous_params) |> Enum.join(", ")
      )
    else
      changeset
    end
  end
end
