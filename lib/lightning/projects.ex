defmodule Lightning.Projects do
  @moduledoc """
  The Projects context.
  """

  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Lightning.Accounts.User
  alias Lightning.Accounts.UserNotifier
  alias Lightning.Accounts.UserToken
  alias Lightning.Config
  alias Lightning.ExportUtils
  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.Step
  alias Lightning.Projects.Audit
  alias Lightning.Projects.Events
  alias Lightning.Projects.File
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Projects.ProjectUser
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.RunStep
  alias Lightning.Services.AccountHook
  alias Lightning.Services.ProjectHook
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkOrder

  require Logger

  defmodule ProjectOverviewRow do
    @moduledoc """
    Represents a summarized view of a project for a user, used in the project overview table.
    """
    defstruct [
      :id,
      :name,
      :role,
      :workflows_count,
      :collaborators_count,
      :last_updated_at
    ]
  end

  def get_projects_overview(user, opts \\ [])

  def get_projects_overview(%User{id: user_id, support_user: true}, opts) do
    support_projects =
      from(p in Project,
        left_join: w in assoc(p, :workflows),
        left_join: pu_all in assoc(p, :project_users),
        where: p.allow_support_access and is_nil(w.deleted_at),
        group_by: [p.id],
        select: %ProjectOverviewRow{
          id: p.id,
          name: p.name,
          role: fragment("'support' as role"),
          workflows_count: count(w.id, :distinct),
          collaborators_count: count(pu_all.user_id, :distinct),
          last_updated_at: max(w.updated_at)
        }
      )
      |> Repo.all()

    user_projects =
      user_id
      |> projects_overview_query()
      |> Repo.all()

    {sort_key, sort_direction} = Keyword.get(opts, :order_by, {:name, :asc})

    [user_projects, support_projects]
    |> Enum.concat()
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&Map.get(&1, sort_key), sort_direction)
  end

  def get_projects_overview(%User{id: user_id}, opts) do
    order_by = Keyword.get(opts, :order_by, {:name, :asc})

    user_id
    |> projects_overview_query()
    |> order_by(^dynamic_order_by(order_by))
    |> Repo.all()
  end

  defp projects_overview_query(user_id) do
    from(p in Project,
      left_join: w in assoc(p, :workflows),
      inner_join: pu in assoc(p, :project_users),
      left_join: pu_all in assoc(p, :project_users),
      where: pu.user_id == ^user_id and is_nil(w.deleted_at),
      group_by: [p.id, pu.role],
      select: %ProjectOverviewRow{
        id: p.id,
        name: p.name,
        role: pu.role,
        workflows_count: count(w.id, :distinct),
        collaborators_count: count(pu_all.user_id, :distinct),
        last_updated_at: max(w.updated_at)
      }
    )
  end

  defp dynamic_order_by({:name, :asc}),
    do: {:asc_nulls_last, dynamic([p], field(p, :name))}

  defp dynamic_order_by({:name, :desc}),
    do: {:desc_nulls_last, dynamic([p], field(p, :name))}

  defp dynamic_order_by({:last_updated_at, :asc}),
    do: {:asc_nulls_last, dynamic([_p, w, _pu, _pu_all], max(w.updated_at))}

  defp dynamic_order_by({:last_updated_at, :desc}),
    do: {:desc_nulls_last, dynamic([_p, w, _pu, _pu_all], max(w.updated_at))}

  @doc """
  Perform, when called with %{"type" => "purge_deleted"}
  will find projects that are ready for permanent deletion and purge them.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"project_id" => project_id, "type" => "purge_deleted"}
      }) do
    project_id |> get_project!() |> delete_project()

    :ok
  end

  def perform(%Oban.Job{args: %{"type" => "purge_deleted"}}) do
    jobs =
      from(p in Project,
        where: p.scheduled_deletion <= ago(0, "second")
      )
      |> Repo.all()
      |> Enum.map(fn project ->
        new(%{project_id: project.id, type: "purge_deleted"}, max_attempts: 3)
      end)

    Oban.insert_all(Lightning.Oban, jobs)

    :ok
  end

  def perform(%Oban.Job{
        args: %{"project_id" => project_id, "type" => "data_retention"}
      }) do
    project = get_project!(project_id)
    delete_history_for(project)
    wipe_dataclips_for(project)

    :ok
  end

  def perform(%Oban.Job{args: %{"type" => "data_retention"}}) do
    jobs =
      list_projects_having_history_retention()
      |> Enum.map(fn project ->
        new(%{project_id: project.id, type: "data_retention"}, max_attempts: 3)
      end)

    Oban.insert_all(Lightning.Oban, jobs)

    :ok
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
  Lists all projects that have history retention
  """
  @spec list_projects_having_history_retention() :: [] | [Project.t(), ...]
  def list_projects_having_history_retention do
    Repo.all(from(p in Project, where: not is_nil(p.history_retention_period)))
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
  Should input or output dataclips be saved for runs in this project?
  """
  def save_dataclips?(id) do
    from(
      p in Project,
      where: p.id == ^id,
      select: p.retention_policy
    )
    |> Repo.one!()
    |> case do
      :retain_all -> true
      :erase_all -> false
    end
  end

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
      preload: [:project, user: u]
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
  def create_project(attrs \\ %{}, schedule_email? \\ true) do
    Repo.transact(fn ->
      with {:ok, project} <- ProjectHook.handle_create_project(attrs) do
        if schedule_email? do
          schedule_project_addition_emails(%Project{project_users: []}, project)
        end

        {:ok, project}
      end
    end)
    |> tap(fn result ->
      with {:ok, project} <- result, do: Events.project_created(project)
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
  def update_project(%Project{} = project, attrs, user \\ nil) do
    changeset =
      project
      |> Project.changeset(attrs)
      |> ProjectHook.handle_project_validation()

    Multi.new()
    |> Multi.update(:project, changeset)
    |> maybe_audit_changes(changeset, user)
    |> Repo.transaction()
    |> case do
      {:ok, %{project: updated_project}} ->
        if retention_setting_updated?(changeset) do
          send_data_retention_change_email(updated_project)
        end

        {:ok, updated_project}

      {:error, :project, changeset, _changes_so_far} ->
        {:error, changeset}

      # 2024-10-29 Not tested at module-level
      # due to the difficulty of simulating a failure
      # without mocking
      {:error, _operation, _changeset, _changes_so_far} ->
        {:error, :not_related_to_project}
    end
  end

  defp maybe_audit_changes(multi, _changeset, nil), do: multi

  defp maybe_audit_changes(multi, changeset, user) do
    multi
    |> Audit.derive_events(changeset, user)
  end

  @spec update_project_with_users(Project.t(), map(), boolean()) ::
          {:ok, Project.t()} | {:error, Ecto.Changeset.t()}
  def update_project_with_users(
        %Project{} = project,
        attrs,
        notify_users \\ true
      ) do
    project = Repo.preload(project, :project_users)

    result =
      project
      |> Project.project_with_users_changeset(attrs)
      |> Repo.update()

    if notify_users do
      with {:ok, updated_project} <- result do
        schedule_project_addition_emails(project, updated_project)
      end
    end

    result
  end

  defp retention_setting_updated?(changeset) do
    Map.has_key?(changeset.changes, :history_retention_period) or
      Map.has_key?(changeset.changes, :dataclip_retention_period)
  end

  defp send_data_retention_change_email(updated_project) do
    users_query =
      from pu in Ecto.assoc(updated_project, :project_users),
        join: u in assoc(pu, :user),
        where: pu.role in ^[:admin, :owner],
        select: u

    users = Repo.all(users_query)

    Enum.each(users, fn user ->
      UserNotifier.send_data_retention_change_email(
        user,
        updated_project
      )
    end)
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

  @spec add_project_users(Project.t(), [map(), ...], boolean()) ::
          {:ok, [ProjectUser.t(), ...]} | {:error, Ecto.Changeset.t()}
  def add_project_users(project, project_users, notify_users \\ true) do
    project = Repo.preload(project, :project_users)
    # include the current list to ensure project owner validations work correctly
    current_users = Enum.map(project.project_users, fn pu -> %{id: pu.id} end)
    params = %{project_users: project_users ++ current_users}

    with {:ok, updated_project} <-
           update_project_with_users(project, params, notify_users) do
      {:ok, updated_project.project_users}
    end
  end

  defp schedule_project_addition_emails(old_project, updated_project) do
    existing_user_ids = Enum.map(old_project.project_users, & &1.user_id)

    emails =
      updated_project.project_users
      |> Enum.reject(fn pu -> pu.user_id in existing_user_ids end)
      |> Enum.map(fn pu ->
        UserNotifier.new(%{type: "project_addition", project_user_id: pu.id})
      end)

    Oban.insert_all(Lightning.Oban, emails)
  end

  @doc """
  Deletes a project user and removes their credentials from the project.

  This function:
  1. Deletes the association between the user and the project
  2. Removes any credentials owned by the user from the project

  All operations are performed within a transaction for data consistency.

  ## Parameters
    - `project_user`: The `ProjectUser` struct to be deleted

  ## Returns
    - The deleted `ProjectUser` struct
  """
  @spec delete_project_user!(ProjectUser.t()) :: ProjectUser.t()
  def delete_project_user!(%ProjectUser{} = project_user) do
    project_user =
      %{user_id: user_id, project_id: project_id} =
      Repo.preload(project_user, [:user, :project])

    Repo.transaction(fn ->
      from(pc in Lightning.Projects.ProjectCredential,
        join: c in Lightning.Credentials.Credential,
        on: c.id == pc.credential_id,
        where: c.user_id == ^user_id and pc.project_id == ^project_id
      )
      |> Repo.delete_all()

      Repo.delete!(project_user)
    end)
    |> case do
      {:ok, project_user} -> project_user
      {:error, error} -> raise error
    end
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

    with {:ok, project} <- ProjectHook.handle_delete_project(project) do
      Logger.debug(fn ->
        # coveralls-ignore-start
        "Project ##{project.id} deleted."
        # coveralls-ignore-stop
      end)

      Events.project_deleted(project)

      {:ok, project}
    end
  end

  @spec delete_project_async(Project.t()) :: {:ok, Oban.Job.t()}
  def delete_project_async(project) do
    job = new(%{project_id: project.id, type: "purge_deleted"}, max_attempts: 3)

    {:ok, _} = Oban.insert(Lightning.Oban, job)
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

  def list_workflows(project) do
    project_workflows_query(project)
    |> Repo.all()
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

  @doc """
  Builds a query to retrieve projects associated with a user.

  ## Parameters
    - user: The user struct for which projects are being queried.
    - opts: Keyword list of options including :include for associations to preload and :order_by for sorting.

  ## Returns
    - An Ecto queryable struct to fetch projects.
  """
  @spec projects_for_user_query(user :: User.t()) ::
          Ecto.Queryable.t()
  def projects_for_user_query(%User{id: user_id}) do
    from(p in Project,
      join: pu in assoc(p, :project_users),
      where: pu.user_id == ^user_id and is_nil(p.scheduled_deletion)
    )
  end

  @doc """
  Fetches projects for a given user from the database.

  ## Parameters
  - user: The user struct for which projects are being queried.
  - opts: Keyword list of options including :include for associations to preload and :order_by for sorting.

  ## Returns
  - A list of projects associated with the user.
  """
  @spec get_projects_for_user(user :: User.t()) :: [Project.t()]
  def get_projects_for_user(%User{support_user: true} = user) do
    from(p in Project,
      where: p.allow_support_access and is_nil(p.scheduled_deletion)
    )
    |> union(^projects_for_user_query(user))
    |> Repo.all()
    |> Enum.uniq_by(& &1.id)
  end

  def get_projects_for_user(%User{} = user) do
    user
    |> projects_for_user_query()
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
  @spec export_project(atom(), Ecto.UUID.t(), [Ecto.UUID.t()] | nil) ::
          {:ok, binary}
  def export_project(:yaml, project_id, snapshot_ids \\ nil) do
    project = get_project!(project_id)

    snapshots =
      if snapshot_ids, do: Snapshot.get_all_by_ids(snapshot_ids), else: nil

    {:ok, _yaml} = ExportUtils.generate_new_yaml(project, snapshots)
  end

  @doc """
  Given a project, this function sets a scheduled deletion
  date based on the PURGE_DELETED_AFTER_DAYS environment variable. If no ENV is
  set, this date defaults to NOW but the automatic project purge cronjob will
  never run. (Note that subsequent logins will be blocked for projects pending
  deletion.)
  """
  def schedule_project_deletion(project) do
    Multi.new()
    |> scheduled_project_deletion_changes(project: project)
    |> Repo.transaction()
    |> case do
      {:ok, %{project: updated_project}} -> {:ok, updated_project}
      {:error, _op, changeset, _changes} -> {:error, changeset}
    end
  end

  def scheduled_project_deletion_changes(multi, [{project_op, project}]) do
    date =
      case Lightning.Config.purge_deleted_after_days() do
        nil -> DateTime.utc_now()
        integer -> DateTime.utc_now() |> Timex.shift(days: integer)
      end

    multi
    |> Multi.merge(fn _changes ->
      triggers = project_triggers_query(project) |> Repo.all()

      Enum.reduce(triggers, Multi.new(), fn trigger, multi ->
        Multi.update(
          multi,
          "update_trigger#{trigger.id}",
          Trigger.changeset(trigger, %{"enabled" => false})
        )
      end)
    end)
    |> Multi.update(
      project_op,
      Ecto.Changeset.change(project, %{
        scheduled_deletion: DateTime.truncate(date, :second)
      })
    )
    |> Multi.run("notify_users#{project.id}", fn _repo, _changes ->
      :ok =
        Ecto.assoc(project, :users)
        |> Repo.all()
        |> Enum.each(fn user ->
          UserNotifier.notify_project_deletion(
            user,
            project
          )
        end)

      {:ok, nil}
    end)
  end

  @doc """
  Deletes project work orders in batches
  """
  @spec delete_project_workorders(Project.t(), non_neg_integer()) :: :ok
  def delete_project_workorders(project, batch_size \\ 1000) do
    :ok =
      project
      |> project_workorders_query()
      |> delete_workorders_history(batch_size)
  end

  @doc """
  Deletes project dataclips in batches
  """
  @spec delete_project_dataclips(Project.t(), non_neg_integer()) :: :ok
  def delete_project_dataclips(project, batch_size \\ 1000) do
    project
    |> project_dataclips_query()
    |> delete_dataclips(batch_size)
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

  defp wipe_dataclips_for(%Project{dataclip_retention_period: period} = project)
       when is_integer(period) do
    update_query =
      from d in Lightning.Invocation.Query.wipe_dataclips(),
        where: d.project_id == ^project.id,
        where: d.inserted_at < ago(^period, "day")

    {count, _} = Repo.update_all(update_query, [])

    {:ok, count}
  end

  defp wipe_dataclips_for(_project) do
    {:error, :missing_dataclip_retention_period}
  end

  defp delete_history_for(
         %Project{
           history_retention_period: period_days
         } = project
       )
       when is_integer(period_days) do
    :ok =
      project
      |> project_workorders_query()
      |> delete_workorders_history(
        Config.activity_cleanup_chunk_size(),
        period_days
      )

    dataclips_query =
      from d in Dataclip,
        as: :dataclip,
        where: d.project_id == ^project.id,
        where: d.inserted_at < ago(^period_days, "day"),
        left_join: wo in WorkOrder,
        on: d.id == wo.dataclip_id,
        left_join: r in Run,
        on: d.id == r.dataclip_id,
        left_join: s in Step,
        on: d.id == s.input_dataclip_id or d.id == s.output_dataclip_id,
        where: is_nil(wo.id) and is_nil(r.id) and is_nil(s.id),
        select: d.id

    delete_dataclips(
      dataclips_query,
      Config.activity_cleanup_chunk_size()
    )

    :ok
  end

  defp delete_history_for(_project) do
    {:error, :missing_history_retention_period}
  end

  defp delete_workorders_history(
         project_workorders_query,
         batch_size,
         retention_period_days \\ nil
       ) do
    workorders_query =
      if retention_period_days do
        where(
          project_workorders_query,
          [wo],
          wo.last_activity < ago(^retention_period_days, "day")
        )
      else
        project_workorders_query
      end

    workorders_delete_query =
      WorkOrder
      |> with_cte("workorders_to_delete",
        as: ^limit(workorders_query, ^batch_size)
      )
      |> join(:inner, [wo], wtd in "workorders_to_delete", on: wo.id == wtd.id)

    steps_delete_query =
      Step
      |> join(:inner, [s], assoc(s, :runs), as: :runs)
      |> with_cte("workorders_to_delete",
        as: ^limit(workorders_query, ^batch_size)
      )
      |> join(:inner, [runs: r], wtd in "workorders_to_delete",
        on: r.work_order_id == wtd.id
      )

    workorders_count = Repo.aggregate(workorders_query, :count)

    for _i <- 1..ceil(workorders_count / batch_size) do
      Repo.transaction(
        fn ->
          {_count, _} = Repo.delete_all(steps_delete_query, returning: false)

          {_count, _} =
            Repo.delete_all(workorders_delete_query, returning: false)
        end,
        timeout: Config.default_ecto_database_timeout() * 3
      )
    end

    # If it's on a retention cleanup, it also deletes unused snapshots after the workorders deletion.
    # Otherwise, it's a cleanup for the whole project when the snapshots are automatically deleted
    # by the workflows deletion.
    if retention_period_days do
      {count, _} = delete_unused_snapshots(project_workorders_query)

      Logger.info("Deleted #{count} unused snapshots")
    end

    :ok
  end

  defp delete_unused_snapshots(project_query) do
    # Find all snapshots for workflows in this project
    snapshots_query =
      from(s in Snapshot,
        join: w in assoc(s, :workflow),
        join: wo in subquery(project_query),
        on: wo.workflow_id == w.id
      )

    # Find snapshots that are current versions of workflows
    current_snapshots =
      from(s in snapshots_query,
        join: w in assoc(s, :workflow),
        where: s.lock_version == w.lock_version
      )

    # Find snapshots still referenced by workorders
    referenced_snapshots =
      from(s in snapshots_query,
        join: wo in WorkOrder,
        on: wo.snapshot_id == s.id
      )

    # Delete snapshots that aren't current and aren't referenced
    delete_query =
      from(s in snapshots_query,
        where:
          s.id not in subquery(current_snapshots |> select([s], s.id)) and
            s.id not in subquery(referenced_snapshots |> select([s], s.id))
      )

    Repo.delete_all(delete_query, returning: false)
  end

  defp delete_dataclips(dataclips_query, batch_size) do
    dataclips_count = Repo.aggregate(dataclips_query, :count)

    dataclips_delete_query =
      Dataclip
      |> with_cte("dataclips_to_delete",
        as: ^limit(dataclips_query, ^batch_size)
      )
      |> join(:inner, [d], dtd in "dataclips_to_delete", on: d.id == dtd.id)

    for _i <- 1..ceil(dataclips_count / batch_size) do
      {_count, _dataclips} =
        Repo.delete_all(dataclips_delete_query,
          returning: false,
          timeout: Config.default_ecto_database_timeout() * 2
        )
    end

    :ok
  end

  def invite_collaborators(project, collaborators, inviter) do
    Multi.new()
    |> Multi.put(:collaborators, collaborators)
    |> Multi.merge(&register_users/1)
    |> Multi.run(:add_users_to_project, fn _repo, changes ->
      add_users_to_project(changes, project, collaborators)
    end)
    |> Multi.run(:send_invitations, fn _repo, changes ->
      send_invitations(changes, project, inviter)
    end)
    |> execute_transaction()
  end

  defp execute_transaction(%Ecto.Multi{} = multi) do
    case Repo.transaction(multi) do
      {:ok, changes} -> {:ok, changes}
      {:error, _op, changeset, _changes} -> {:error, changeset}
    end
  end

  defp add_users_to_project(changes, project, collaborators) do
    project_users = build_project_users_list(collaborators, changes)

    case add_project_users(project, project_users, false) do
      {:ok, project_users} -> {:ok, %{project_users: project_users}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp register_users(%{collaborators: collaborators}) do
    Enum.reduce(collaborators, Multi.new(), fn collaborator, multi ->
      user_params =
        collaborator
        |> Map.take([:first_name, :last_name, :email])
        |> Map.put(:password, generate_random_password())

      Multi.run(
        multi,
        {:new_user, collaborator.email},
        fn _repo, _changes ->
          with {:error, _reason} <- AccountHook.handle_register_user(user_params) do
            {:error, :user_registration_failed}
          end
        end
      )
    end)
  end

  defp generate_random_password do
    :crypto.strong_rand_bytes(12)
    |> Base.encode64(padding: false)
  end

  defp build_project_users_list(collaborators, changes) do
    Enum.map(collaborators, fn collaborator ->
      user = changes[{:new_user, collaborator.email}]
      %{role: collaborator.role, user_id: user.id}
    end)
  end

  defp send_invitations(changes, project, inviter) do
    case generate_user_tokens(changes) do
      {:ok, tokens} ->
        Enum.each(tokens, fn {:encoded_token, email, encoded_token} ->
          user = find_user_by_email(changes, email)
          role = find_role_by_email(changes, email)

          UserNotifier.deliver_project_invitation_email(
            user,
            inviter,
            project,
            role,
            encoded_token
          )
        end)

        {:ok, :invitations_sent}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_user_tokens(changes) do
    Enum.reduce_while(changes, {:ok, []}, fn
      {{:new_user, email}, user}, {:ok, acc} ->
        {encoded_token, user_token} =
          UserToken.build_email_token(user, "reset_password", user.email)

        case Repo.insert(user_token) do
          {:ok, _} ->
            {:cont, {:ok, [{:encoded_token, email, encoded_token} | acc]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end

      _, acc ->
        {:cont, acc}
    end)
  end

  defp find_user_by_email(changes, email) do
    Enum.find_value(changes, fn {key, val} ->
      if key == {:new_user, email}, do: val
    end)
  end

  defp find_role_by_email(changes, email) do
    Enum.find_value(changes[:collaborators], fn collaborator ->
      if collaborator.email == email, do: collaborator.role
    end)
  end

  def list_project_files(%Project{id: project_id}, opts \\ []) do
    sort_order = Keyword.get(opts, :sort, :desc)

    from(pf in File,
      where: pf.project_id == ^project_id,
      order_by: [{^sort_order, pf.inserted_at}],
      preload: [:created_by]
    )
    |> Repo.all()
  end

  def find_users_to_notify_of_trigger_failure(project_id) do
    query =
      from u in User,
        join: pu in assoc(u, :project_users),
        where:
          pu.project_id == ^project_id and
            (pu.role in ^[:admin, :owner] or u.role == ^:superuser)

    query |> Repo.all()
  end
end
