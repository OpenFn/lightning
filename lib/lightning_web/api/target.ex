defmodule LightningWeb.API.Target do
  @moduledoc """
  Resolves the project an API action works on, asks the policy whether the
  caller may act there, and only then looks up the record inside it. It takes
  the `Lightning.Scope` that `LightningWeb.Plugs.AuthorizeAction` assigned, and
  every refusal it returns is one `LightningWeb.API.FallbackController`
  answers.

  A caller the policy refuses gets the same 403 whether the record exists, is
  missing or has an id that isn't a UUID, and only a caller it permits learns
  which.
  """
  alias Lightning.Policies.Permissions
  alias Lightning.Projects.Project
  alias Lightning.Scope
  alias LightningWeb.API.Request

  @type permission :: {policy :: atom(), action :: atom()}

  @typedoc """
  What identifies a project: an id the request sent, as a
  `t:LightningWeb.API.Request.param/0`, or a record loaded from the database,
  a `%Project{}` or anything carrying its `project_id`. A bare id is not
  accepted, so an id that isn't a UUID is always refused naming where the
  request sent it.
  """
  @type subject ::
          Request.param()
          | Project.t()
          | %{required(:project_id) => Ecto.UUID.t(), optional(any()) => any()}

  @typedoc """
  Looks a record up by id inside a project, given the project's id and the
  record's.
  """
  @type get(record) :: (Ecto.UUID.t(), Ecto.UUID.t() ->
                          {:ok, record} | {:error, :not_found})

  @doc """
  The project `subject` identifies, once the caller may apply the permission to
  it.

  A project `subject` doesn't identify is refused as `Lightning.Scope.fetch/2`
  refuses it.

      Target.project(conn.assigns.scope, Request.param(conn, "project_id"),
        {:project_users, :access_project}
      )
  """
  @spec project(Scope.t() | Scope.actor(), subject(), permission()) ::
          {:ok, Project.t()} | {:error, term()}
  def project(scope, subject, {policy, action}) do
    with {:ok, scope} <- fetch(scope, subject),
         :ok <- Permissions.permit(policy, action, scope, scope.project),
         do: {:ok, scope.project}
  end

  @doc """
  The project `subject` names, as `project/3` answers it, or a new, unsaved
  `%Project{}` when no project has that id, or `subject` carries no id, and the
  caller holds `create_permission`.

  An id that isn't a UUID is `{:error, {:invalid_id, location}}` to a caller
  who holds `create_permission`. An id held by a project the caller may not
  apply `permission` to is that refusal, never a new project.
  """
  @spec project_or_new(
          Scope.t() | Scope.actor(),
          Request.param(),
          permission(),
          permission()
        ) ::
          {:ok, Project.t()} | {:error, term()}
  def project_or_new(scope, {_location, nil}, _permission, create_permission),
    do: new_project(scope, create_permission)

  def project_or_new(scope, subject, permission, create_permission) do
    case project(scope, subject, permission) do
      {:error, :no_such_project} ->
        new_project(scope, create_permission)

      {:error, {:invalid_id, _location}} = invalid ->
        with :ok <- permit(scope, create_permission), do: invalid

      found_or_refused ->
        found_or_refused
    end
  end

  defp new_project(scope, create_permission) do
    with :ok <- permit(scope, create_permission), do: {:ok, %Project{}}
  end

  defp permit(scope, {policy, action}),
    do: Permissions.permit(policy, action, scope, nil)

  @doc """
  The record `param` names on a route whose parent is the instance and whose
  record sits in no project, such as `/api/credentials/:id`, once the caller
  may apply the permission to it. `get` is given the id once it parses as a
  UUID and answers `{:ok, record}` or `{:error, :not_found}`.

  Only a caller who may apply the permission to the instance, asked of the
  policy with a nil subject, learns that an id names nothing
  (`{:error, :not_found}`) or isn't a UUID
  (`{:error, {:invalid_id, location}}`). Anyone else gets
  `{:error, :no_standing}`, as for a record they can't see.

      Target.record(scope, Request.param(conn, "id"),
        {:credentials, :see_credential},
        &fetch_credential/1
      )
  """
  @spec record(
          Scope.t(),
          Request.param(),
          permission(),
          (Ecto.UUID.t() -> {:ok, record} | {:error, :not_found})
        ) :: {:ok, record} | {:error, term()}
        when record: term()
  def record(%Scope{} = scope, param, {policy, action}, get) do
    case with({:ok, id} <- Request.id(param), do: get.(id)) do
      {:ok, record} ->
        with :ok <- Permissions.permit(policy, action, scope, record),
             do: {:ok, record}

      {:error, reason} ->
        case Permissions.permit(policy, action, scope, nil) do
          :ok -> {:error, reason}
          _refused -> {:error, :no_standing}
        end
    end
  end

  @doc """
  The record `id_param` names in the project `subject` identifies, once the
  caller may apply the permission to that project. The id is checked as a UUID
  only then, and `get` is given the project's id and the record's.

      Target.in_project(scope, Request.param(conn, "project_id"),
        {:project_users, :edit_workflow},
        Request.param(conn, "id"),
        &Workflows.get_workflow_for_project/2
      )
  """
  @spec in_project(
          Scope.t() | Scope.actor(),
          subject(),
          permission(),
          Request.param(),
          get(record)
        ) :: {:ok, record} | {:error, term()}
        when record: term()
  def in_project(scope, subject, permission, id_param, get) do
    with {:ok, project} <- project(scope, subject, permission),
         {:ok, id} <- Request.id(id_param),
         do: get.(project.id, id)
  end

  @doc """
  The record `id_param` names on a route whose parent is the instance, such as
  `/api/jobs/:id`, once the caller may apply the permission to the project the
  record sits in. `locate` answers the id of that project, and the record is
  then looked up in it with `get`, as `in_project/5` does on the nested route.

  Only an operator learns that an id names no record (`{:error, :not_found}`)
  or isn't a UUID (`{:error, {:invalid_id, location}}`). Anyone else gets
  `{:error, :no_standing}` for both. A record in a project the caller may not
  apply the permission to is `{:error, :no_standing}` or
  `{:error, :forbidden}`. All three answer 403 `forbidden`.

  A project deleted between locating it and reading it is
  `{:error, :no_such_project}` to a caller who may learn which projects exist,
  as `Lightning.Scope.fetch/2` answers it.

      Target.in_project_of(scope, Request.param(conn, "id"),
        {:project_users, :access_project},
        &Jobs.get_project_id/1,
        &Jobs.get_job_for_project/2
      )
  """
  @spec in_project_of(
          Scope.t(),
          Request.param(),
          permission(),
          (Ecto.UUID.t() -> {:ok, Ecto.UUID.t()} | {:error, :not_found}),
          get(record)
        ) :: {:ok, record} | {:error, term()}
        when record: term()
  def in_project_of(%Scope{} = scope, id_param, permission, locate, get) do
    with {:ok, id} <- Request.id(id_param),
         {:ok, project_id} <- locate.(id) do
      case project(scope, %{project_id: project_id}, permission) do
        {:ok, project} -> get.(project.id, id)
        {:error, reason} = refused when reason != :invalid_id -> refused
      end
    else
      {:error, reason} -> unknown_record(scope, reason)
    end
  end

  defp unknown_record(scope, reason) do
    if Scope.operator?(scope),
      do: {:error, reason},
      else: {:error, :no_standing}
  end

  defp fetch(scope, {location, id}) do
    case Scope.fetch(scope, id) do
      {:error, :invalid_id} -> {:error, {:invalid_id, location}}
      result -> result
    end
  end

  defp fetch(scope, record) when is_map(record), do: Scope.fetch(scope, record)
end
