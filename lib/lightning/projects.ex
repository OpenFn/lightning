defmodule Lightning.Projects do
  @moduledoc """
  The Projects context.
  """

  import Ecto.Query, warn: false
  alias Lightning.Repo

  alias Lightning.Projects.{Project, ProjectCredential}
  alias Lightning.Accounts.User
  alias Lightning.ExportUtils

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
  Deletes a project.

  ## Examples

      iex> delete_project(project)
      {:ok, %Project{}}

      iex> delete_project(project)
      {:error, %Ecto.Changeset{}}

  """
  def delete_project(%Project{} = project) do
    Repo.delete(project)
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

  @spec export_project(:yaml, any) :: {:ok, binary}
  @doc """
  Exports a project as yaml.

  ## Examples

      iex> export_project(:yaml, project_id)
      {:ok, string}

  """
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
    ImportUtils.import_multi_for_project(project_data, user)
    |> Repo.transaction()
  end
end

defmodule ImportUtils do
  @moduledoc """
  Module that expose a function building a multi for importing a project yaml (via a map)
  """

  import Ecto.Changeset

  alias Ecto.Multi

  alias Lightning.Projects.Project
  alias Lightning.Workflows.Workflow
  alias Lightning.Credentials.Credential
  alias Lightning.Jobs.Job

  def import_multi_for_project(project_data, user) do
    Multi.new()
    |> put_project(project_data, user)
    |> put_credentials(project_data, user)
    |> put_workflows(project_data)
  end

  defp put_project(multi, project_data, user) do
    multi
    |> Multi.insert(:project, fn _ ->
      id = Ecto.UUID.generate()

      attrs =
        project_data
        |> Map.put(:id, id)
        |> Map.put(:project_users, [
          %{
            project_id: id,
            user_id: user.id
          }
        ])

      %Project{}
      |> Project.changeset(attrs)
    end)
  end

  def import_workflow_changeset(
        workflow,
        %{workflow_id: workflow_id, project_id: project_id},
        import_transaction
      ) do
    workflow =
      workflow
      |> Map.put(:id, workflow_id)
      |> Map.put(:project_id, project_id)

    %Workflow{}
    |> cast(
      workflow,
      [:name, :project_id, :id]
    )
    |> cast_assoc(:jobs,
      with:
        {ImportUtils, :import_job_changeset, [workflow_id, import_transaction]}
    )
  end

  def import_job_changeset(job, attrs, workflow_id, import_transaction) do
    credential_key = attrs[:credential]

    if credential_key do
      credential = import_transaction["credential::#{credential_key}"]

      if credential do
        %{project_credentials: [%{id: project_credential_id}]} = credential
        attrs = Map.put(attrs, :project_credential_id, project_credential_id)

        job
        |> Job.changeset(attrs, workflow_id)
      else
        job
        |> Job.changeset(attrs, workflow_id)
        |> add_error(:credential, "not found in project input")
      end
    else
      job
      |> Job.changeset(attrs, workflow_id)
    end
  end

  defp put_workflows(multi, project_data) do
    workflows = project_data[:workflows] || []

    workflows
    |> Enum.reduce(multi, fn workflow, m ->
      workflow_id = Ecto.UUID.generate()

      Multi.insert(m, "workflow::#{workflow_id}", fn %{project: project} =
                                                       import_transaction ->
        import_workflow_changeset(
          workflow,
          %{workflow_id: workflow_id, project_id: project.id},
          import_transaction
        )
      end)
    end)
  end

  defp put_credentials(multi, project_data, user) do
    credentials = project_data[:credentials] || []

    credentials
    |> Enum.reduce(multi, fn credential, m ->
      Multi.insert(m, "credential::#{credential.key}", fn %{
                                                            project: project
                                                          } ->
        id = Ecto.UUID.generate()

        attrs =
          credential
          |> Map.put(:id, id)
          |> Map.put(:user_id, user.id)
          |> Map.put(:project_credentials, [
            %{
              project_id: project.id,
              credential_id: id
            }
          ])

        %Credential{}
        |> Credential.changeset(attrs)
      end)
    end)
  end
end
