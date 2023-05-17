defmodule Lightning.Projects do
  @moduledoc """
  The Projects context.
  """

  import Ecto.Query, warn: false
  alias Lightning.Attempt
  alias Lightning.AttemptRun
  alias Lightning.Jobs.Trigger
  alias Lightning.Jobs.Job
  alias Lightning.Projects.ProjectUser
  alias Lightning.Repo

  alias Lightning.Projects.{Project, ProjectCredential}
  alias Lightning.Accounts.User
  alias Lightning.ExportUtils
  alias Lightning.Workflows.Workflow
  alias Lightning.InvocationReason
  alias Lightning.Invocation.{Run, Dataclip}
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
  def get_project_with_users!(id) do
    from(p in Project, where: p.id == ^id, preload: [project_users: :user])
    |> Repo.one!()
  end

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
  Deletes a project and its related data, including workflows, work orders,
  runs, jobs, attempts, triggers, project users, project credentials, and dataclips

  ## Examples

      iex> delete_project(project)
      {:ok, %Project{}}

      iex> delete_project(project)
      {:error, %Ecto.Changeset{}}

  """

  def delete_project(%Project{} = project) do
    Repo.transaction(fn ->
      project_attempts_query(project) |> Repo.delete_all()

      project_attempt_run_query(project) |> Repo.delete_all()

      project_workorders_query(project) |> Repo.delete_all()

      project_users_invocation_reasons(project) |> Repo.delete_all()

      project_runs_query(project) |> Repo.delete_all()

      project_jobs_query(project) |> Repo.delete_all()

      project_workflows_invocation_reason(project) |> Repo.delete_all()

      project_triggers_query(project) |> Repo.delete_all()

      project_workflows_query(project) |> Repo.delete_all()

      project_users_query(project) |> Repo.delete_all()

      project_credentials_query(project) |> Repo.delete_all()

      project_dataclips_query(project) |> Repo.delete_all()

      {:ok, project} = Repo.delete(project)
      project
    end)
  end

  def project_workflows_invocation_reason(project) do
    from(ir in InvocationReason,
      join: tr in assoc(ir, :trigger),
      join: w in assoc(tr, :workflow),
      join: d in assoc(ir, :dataclip),
      where: w.project_id == ^project.id or d.project_id == ^project.id
    )
  end

  def project_users_invocation_reasons(project) do
    from(ir in InvocationReason,
      join: u in assoc(ir, :user),
      join: pu in assoc(u, :project_users),
      join: p in assoc(pu, :project),
      where: p.id == ^project.id
    )
  end

  def project_attempts_query(project) do
    from(att in Attempt,
      join: wo in assoc(att, :work_order),
      join: w in assoc(wo, :workflow),
      where: w.project_id == ^project.id
    )
  end

  def project_attempt_run_query(project) do
    from(ar in AttemptRun,
      join: att in assoc(ar, :attempt),
      join: wo in assoc(att, :work_order),
      join: w in assoc(wo, :workflow),
      where: w.project_id == ^project.id
    )
  end

  def project_workorders_query(project) do
    from(wo in WorkOrder,
      join: w in assoc(wo, :workflow),
      where: w.project_id == ^project.id
    )
  end

  def project_jobs_query(project) do
    from(j in Job,
      join: w in assoc(j, :workflow),
      where: w.project_id == ^project.id
    )
  end

  def project_runs_query(project) do
    from(r in Run,
      join: j in assoc(r, :job),
      join: w in assoc(j, :workflow),
      where: w.project_id == ^project.id
    )
  end

  def project_workflows_query(project) do
    from(w in Workflow, where: w.project_id == ^project.id)
  end

  @spec project_users_query(atom | %{:id => any, optional(any) => any}) ::
          Ecto.Query.t()
  def project_users_query(project) do
    from(p in ProjectUser, where: p.project_id == ^project.id)
  end

  def project_credentials_query(project) do
    from(pc in ProjectCredential, where: pc.project_id == ^project.id)
  end

  def project_dataclips_query(project) do
    from(d in Dataclip, where: d.project_id == ^project.id)
  end

  def project_triggers_query(project) do
    from(tr in Trigger,
      join: w in assoc(tr, :workflow),
      where: w.project_id == ^project.id
    )
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
end
