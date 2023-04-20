defmodule Lightning.Projects do
  @moduledoc """
  The Projects context.
  """

  import Ecto.Query, warn: false
  alias Lightning.Attempt
  alias Lightning.AttemptRun
  alias Lightning.Jobs.Trigger
  alias Lightning.Projects.ProjectUser
  alias Lightning.Repo

  alias Lightning.Projects.{Importer, Project, ProjectCredential}
  alias Lightning.Accounts.User
  alias Lightning.ExportUtils
  alias Lightning.Workflows.Workflow
  alias Lightning.InvocationReason
  alias Lightning.WorkOrder

  @doc """
  Returns the list of projects.

  ## Examples

      iex> list_projects()
      [%Project{}, ...]

  """
  def list_projects do
    Repo.all(from(p in Project, order_by: p.name))
  end

  @doc """
  Gets a single project.

  Raises `Ecto.NoResultsError` if the Project does not exist.

  ## Examples

      iex> get_project!(123)
      %Project{}

      iex> get_project!(456)
      ** (Ecto.NoResultsError)

  """
  def get_project!(id), do: Repo.get!(Project, id)

  def get_project(id), do: Repo.get(Project, id)

  @doc """
  Gets a single project_user.

  Raises `Ecto.NoResultsError` if the ProjectUser does not exist.

  ## Examples

      iex> get_project_user!(123)
      %ProjectUser{}

      iex> get_project_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_project_user!(id), do: Repo.get!(ProjectUser, id)

  def get_project_user(id), do: Repo.get(ProjectUser, id)

  @doc """
  Gets a single project with it's members via `project_users`.

  Raises `Ecto.NoResultsError` if the Project does not exist.

  ## Examples

      iex> get_project!(123)
      %Project{}

      iex> get_project!(456)
      ** (Ecto.NoResultsError)

  """
  def get_project_with_users!(id),
    do: Repo.get!(Project |> preload(project_users: [:user]), id)

  @doc """
  Creates a project.

  ## Examples

      iex> create_project(%{field: value})
      {:ok, %Project{}}

      iex> create_project(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_project(attrs \\ %{}) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a project.

  ## Examples

      iex> update_project(project, %{field: new_value})
      {:ok, %Project{}}

      iex> update_project(project, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a project user.

  ## Examples

      iex> update_project_user(project_user, %{field: new_value})
      {:ok, %ProjectUser{}}

      iex> update_project_user(projectUser, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_project_user(%ProjectUser{} = project_user, attrs) do
    project_user
    |> ProjectUser.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a project.

  ## Examples

      iex> delete_project(project)
      {:ok, %Project{}}

      iex> delete_project(project)
      {:error, %Ecto.Changeset{}}

  """
  def delete_project(%Project{} = project) do
    workflows =
      from(w in Workflow, where: w.project_id == ^project.id)
      |> Repo.all()

    Repo.transaction(fn ->
      Enum.each(workflows, fn workflow ->
        work_orders = from(w in WorkOrder, where: w.workflow_id == ^workflow.id)

        Enum.each(work_orders |> Repo.all(), fn work_order ->
          attempts = from(a in Attempt, where: a.work_order_id == ^work_order.id)

          # Delete all attemptsrun
          Enum.each(attempts |> Repo.all(), fn attempt ->
            Repo.delete_all(
              from(ar in AttemptRun, where: ar.attempt_id == ^attempt.id)
            )
          end)

          # Delete all attempts
          Repo.delete_all(attempts)
        end)

        # Delete all work_orders
        Repo.delete_all(work_orders)

        # Delete associated invocation reasons for each workflow trigger
        Repo.delete_all(
          from(ir in InvocationReason,
            join: t in assoc(ir, :trigger),
            where: t.workflow_id == ^workflow.id
          )
        )

        jobs =
          from(t in Lightning.Jobs.Job, where: t.workflow_id == ^workflow.id)

        # Delete associated invocation reasons for each run
        Enum.each(jobs |> Repo.all(), fn job ->
          Repo.delete_all(
            from(ir in InvocationReason,
              join: r in assoc(ir, :run),
              where: r.job_id == ^job.id
            )
          )
        end)

        # Delete all jobs
        Repo.delete_all(jobs)

        triggers = from(t in Trigger, where: t.workflow_id == ^workflow.id)
        # Delete all triggers
        Repo.delete_all(triggers)
      end)

      # Delete all project users
      Repo.delete_all(from(p in ProjectUser, where: p.project_id == ^project.id))
      # Delete all project credentials
      Repo.delete_all(
        from(pc in ProjectCredential, where: pc.project_id == ^project.id)
      )

      # Delete all project workflow
      Repo.delete_all(from(w in Workflow, where: w.project_id == ^project.id))

      # Delete associated invocation reasons for dataclip
      Repo.delete_all(
        from(ir in InvocationReason,
          join: d in assoc(ir, :dataclip),
          where: d.project_id == ^project.id
        )
      )

      # Delete project
      {:ok, project} = Repo.delete(project)
      project
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking project changes.

  ## Examples

      iex> change_project(project)
      %Ecto.Changeset{data: %Project{}}

  """
  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.changeset(project, attrs)
  end

  @spec list_project_credentials(project :: Project.t()) :: [
          ProjectCredential.t()
        ]
  def list_project_credentials(%Project{} = project) do
    Ecto.assoc(project, :project_credentials)
    |> preload(:credential)
    |> Repo.all()
  end

  @spec projects_for_user_query(user :: User.t()) :: Ecto.Queryable.t()
  def projects_for_user_query(%User{id: user_id}) do
    from(p in Project,
      join: pu in assoc(p, :project_users),
      where: pu.user_id == ^user_id
    )
  end

  @spec get_projects_for_user(user :: User.t()) :: [Project.t()]
  def get_projects_for_user(user) do
    projects_for_user_query(user)
    |> Repo.all()
  end

  @spec project_user_role_query(user :: User.t(), project :: Project.t()) ::
          Ecto.Queryable.t()
  def project_user_role_query(%User{id: user_id}, %Project{id: project_id}) do
    from(p in Project,
      join: pu in assoc(p, :project_users),
      where: p.id == ^project_id and pu.user_id == ^user_id,
      select: pu.role
    )
  end

  @doc """
  Returns the role of a user in a project.
  Possible roles are :admin, :viewer, :editor, and :owner

  ## Examples

      iex> get_project_user_role(user, project)
      :admin

      iex> get_project_user_role(user, project)
      :viewer

      iex> get_project_user_role(user, project)
      :editor

      iex> get_project_user_role(user, project)
      :owner

  """
  def get_project_user_role(user, project) do
    project_user_role_query(user, project)
    |> Repo.one()
  end

  @spec first_project_for_user(user :: User.t()) :: Project.t() | nil
  def first_project_for_user(user) do
    from(p in Project,
      join: pu in assoc(p, :project_users),
      where: pu.user_id == ^user.id,
      limit: 1
    )
    |> Repo.one()
  end

  def url_safe_project_name(nil), do: ""

  def url_safe_project_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z-_\.\d]+/, "-")
    |> String.replace(~r/^\-+|\-+$/, "")
  end

  def is_member_of?(%Project{id: project_id}, %User{id: user_id}) do
    from(p in Project,
      join: pu in assoc(p, :project_users),
      where: pu.user_id == ^user_id and p.id == ^project_id,
      select: true
    )
    |> Repo.one()
    |> case do
      nil -> false
      true -> true
    end
  end

  def get_project_credential(project_id, credential_id) do
    from(pc in ProjectCredential,
      where:
        pc.credential_id == ^credential_id and
          pc.project_id == ^project_id
    )
    |> Repo.one()
  end

  @doc """
  Exports a project as yaml.

  ## Examples

      iex> export_project(:yaml, project_id)
      {:ok, string}

  """
  @spec export_project(:yaml, any) :: {:ok, binary}
  def export_project(:yaml, project_id) do
    {:ok, yaml} = ExportUtils.generate_new_yaml(project_id)

    {:ok, yaml}
  end

  @spec import_project(any, any) :: {:ok, binary}
  @doc """
  Imports a project as map.

  ## Examples

      iex> import_project(:yaml, project_id)
      {:ok, string}

  """
  def import_project(project_data, user) do
    Importer.import_multi_for_project(project_data, user)
    |> Repo.transaction()
  end
end
