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

  alias Lightning.Accounts.User
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectUser
  alias Lightning.Repo
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow

  @doc """
  Import a project.
  """
  @spec import_document(Project.t() | nil, User.t(), map()) ::
          {:error, Ecto.Changeset.t(Project.t())}
          | {:ok, Project.t()}
  def import_document(nil, %User{} = user, data),
    do: import_document(%Project{}, user, data)

  def import_document(project, %User{} = user, data) do
    project
    |> maybe_reload_project()
    |> parse_document(data)
    |> maybe_add_project_user(user)
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
    |> project_changeset(data)
    |> cast_assoc(:workflows, with: &workflow_changeset/2)
  end

  defp maybe_add_project_user(changeset, user) do
    if needs_initial_project_user?(changeset) do
      changeset |> add_owner(user)
    else
      changeset
    end
  end

  defp needs_initial_project_user?(changeset) do
    changeset
    |> get_field(:project_users)
    |> Enum.empty?()
  end

  defp add_owner(changeset, user) do
    changeset
    |> put_assoc(:project_users, [
      %ProjectUser{user_id: user.id, role: "owner"}
      | changeset |> get_field(:project_users)
    ])
  end

  @doc """
  Load a project by ID, including all workflows and their associated jobs,
  triggers and edges.

  Returns `nil` if the project does not exist.
  """
  @spec load_project(Ecto.UUID.t()) :: Project.t() | nil
  def load_project(id) do
    from(p in Project,
      where: p.id == ^id,
      preload: [:project_users, workflows: [:jobs, :triggers, :edges]]
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

  defp project_changeset(project, attrs) do
    project
    |> cast(attrs, [:id, :name, :description])
    |> validate_required([:id])
    |> validate_extraneous_params()
    |> Project.validate()
  end

  defp workflow_changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [:id, :name, :delete])
    |> validate_required([:id])
    |> maybe_mark_for_deletion()
    |> validate_extraneous_params()
    |> cast_assoc(:jobs, with: &job_changeset/2)
    |> cast_assoc(:triggers, with: &trigger_changeset/2)
    |> cast_assoc(:edges, with: &edge_changeset/2)
    |> Workflow.validate()
  end

  defp job_changeset(job, attrs) do
    job
    |> cast(attrs, [:id, :name, :body, :adaptor, :delete])
    |> validate_required([:id])
    |> unique_constraint(:id, name: :jobs_pkey)
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
    |> unique_constraint(:id, name: :triggers_pkey)
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
      :enabled,
      :condition_expression,
      :condition_type,
      :condition_label,
      :target_job_id,
      :delete
    ])
    |> validate_required([:id])
    |> unique_constraint(:id, name: :workflow_edges_pkey)
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
