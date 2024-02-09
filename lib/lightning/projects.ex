defmodule Lightning.Projects do
  @moduledoc """
  The Projects context.
  """
  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  import Ecto.Query, warn: false

  alias Lightning.Accounts.User
  alias Lightning.Accounts.UserNotifier
  alias Lightning.ExportUtils
  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.Step
  alias Lightning.Projects.Events
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Projects.ProjectUser
  alias Lightning.Projects.ProjectUser
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.RunStep
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkOrder

  require Logger

  @doc """
  Perform, when called with %{"type" => "purge_deleted"}
  will find projects that are ready for permanent deletion and purge them.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "purge_deleted"}}) do
    projects_to_delete =
      from(p in Project,
        where: p.scheduled_deletion <= ago(0, "second")
      )
      |> Repo.all()

    :ok =
      Enum.each(projects_to_delete, fn project -> delete_project(project) end)

    {:ok, %{projects_deleted: projects_to_delete}}
  end

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

  def get_project_user(%Project{id: project_id}, %User{id: user_id}) do
    from(pu in ProjectUser,
      join: p in assoc(pu, :project),
      on: p.id == ^project_id,
      join: u in assoc(pu, :user),
      on: u.id == ^user_id,
      preload: [:user, :project]
    )
    |> Repo.one()
  end

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
  Get all project users for a given project
  """
  def get_project_users!(id) do
    from(pu in ProjectUser,
      join: u in assoc(pu, :user),
      where: pu.project_id == ^id,
      order_by: u.first_name,
      preload: [user: u]
    )
    |> Repo.all()
  end

  @doc """
  Lists emails of users with `:owner` or `:admin` roles in the project
  """
  @spec list_project_admin_emails(Ecto.UUID.t()) :: [String.t(), ...] | []
  def list_project_admin_emails(id) do
    from(pu in ProjectUser,
      join: u in assoc(pu, :user),
      where: pu.project_id == ^id and pu.role in ^[:admin, :owner],
      select: u.email
    )
    |> Repo.all()
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
    |> tap(fn result ->
      with {:ok, project} <- result do
        Events.project_created(project)
      end
    end)
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
  steps, jobs, runs, triggers, project users, project credentials, and dataclips

  ## Examples

      iex> delete_project(project)
      {:ok, %Project{}}

      iex> delete_project(project)
      {:error, %Ecto.Changeset{}}

  """

  def delete_project(%Project{} = project) do
    Logger.debug(fn ->
      # coveralls-ignore-start
      "Deleting project ##{project.id}..."
      # coveralls-ignore-stop
    end)

    Repo.transaction(fn ->
      project_runs_query(project) |> Repo.delete_all()

      project_run_step_query(project) |> Repo.delete_all()

      project_workorders_query(project) |> Repo.delete_all()

      project_steps_query(project) |> Repo.delete_all()

      project_jobs_query(project) |> Repo.delete_all()

      project_triggers_query(project) |> Repo.delete_all()

      project_workflows_query(project) |> Repo.delete_all()

      project_users_query(project) |> Repo.delete_all()

      project_credentials_query(project) |> Repo.delete_all()

      project_dataclips_query(project) |> Repo.delete_all()

      {:ok, project} = Repo.delete(project)

      Logger.debug(fn ->
        # coveralls-ignore-start
        "Project ##{project.id} deleted."
        # coveralls-ignore-stop
      end)

      project
    end)
    |> tap(fn result ->
      with {:ok, _project} <- result do
        Events.project_deleted(project)
      end
    end)
  end

  @spec project_retention_policy_for(Run.t()) ::
          Project.retention_policy_type()
  def project_retention_policy_for(%Run{work_order_id: wo_id}) do
    query =
      from(wo in WorkOrder,
        join: wf in assoc(wo, :workflow),
        join: p in assoc(wf, :project),
        where: wo.id == ^wo_id,
        select: p.retention_policy
      )

    Repo.one(query)
  end

  def project_runs_query(project) do
    from(att in Run,
      join: wo in assoc(att, :work_order),
      join: w in assoc(wo, :workflow),
      where: w.project_id == ^project.id
    )
  end

  def project_run_step_query(project) do
    from(as in RunStep,
      join: att in assoc(as, :run),
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

  def project_steps_query(project) do
    from(s in Step,
      join: j in assoc(s, :job),
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
      where: pu.user_id == ^user_id and is_nil(p.scheduled_deletion)
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

  @spec select_first_project_for_user(user :: User.t()) :: Project.t() | nil
  def select_first_project_for_user(user) do
    from(p in Project,
      join: pu in assoc(p, :project_users),
      where: pu.user_id == ^user.id and is_nil(p.scheduled_deletion),
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

  def member_of?(%Project{id: project_id}, %User{id: user_id}) do
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

  @doc """
  Given a project, this function sets a scheduled deletion
  date based on the PURGE_DELETED_AFTER_DAYS environment variable. If no ENV is
  set, this date defaults to NOW but the automatic project purge cronjob will
  never run. (Note that subsequent logins will be blocked for projects pending
  deletion.)
  """
  def schedule_project_deletion(project) do
    date =
      case Application.get_env(:lightning, :purge_deleted_after_days) do
        nil -> DateTime.utc_now()
        integer -> DateTime.utc_now() |> Timex.shift(days: integer)
      end

    Repo.transaction(fn ->
      triggers = project_triggers_query(project) |> Repo.all()

      triggers
      |> Enum.each(fn trigger ->
        Lightning.Workflows.update_trigger(trigger, %{"enabled" => false})
      end)

      project =
        project
        |> Ecto.Changeset.change(%{
          scheduled_deletion: DateTime.truncate(date, :second)
        })
        |> Repo.update!()

      :ok =
        Ecto.assoc(project, :users)
        |> Repo.all()
        |> Enum.each(fn user ->
          UserNotifier.notify_project_deletion(
            user,
            project
          )
        end)

      project
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the project scheduled_deletion.

  ## Examples

      iex> validate_for_deletion(project)
      %Ecto.Changeset{data: %Project{}}

  """
  def validate_for_deletion(project, attrs) do
    Project.deletion_changeset(project, attrs)
  end

  def cancel_scheduled_deletion(project_id) do
    get_project!(project_id)
    |> Ecto.Changeset.change(%{scheduled_deletion: nil})
    |> Repo.update()
  end
end
