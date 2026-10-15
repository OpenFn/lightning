defmodule LightningWeb.API.CredentialController do
  @moduledoc """
  API controller for credential management.

  Handles creation, retrieval, and deletion of credentials. Credentials are
  used to authenticate with external services and can be associated with
  multiple projects.

  ## Security

  - Credential bodies are excluded from responses for security
  - Users can only delete credentials they own
  - Project access is required to view project credentials

  ## Examples

      GET /api/credentials
      GET /api/credentials?project_id=a1b2c3d4-...
      POST /api/credentials
      GET /api/credentials/a1b2c3d4-...
      PUT /api/credentials/a1b2c3d4-...
      DELETE /api/credentials/a1b2c3d4-...
  """
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Repo
  alias Lightning.Scope
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.PutBody
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  # Both index routes need the `credentials:write` grant, and that is all this
  # plug checks.
  plug AuthorizeAction,
       {:credentials, :list_credentials, fallback: FallbackController}
       when action == :index

  plug AuthorizeAction,
       {:credentials, :edit_credential, fallback: FallbackController}
       when action in [:create, :show, :update]

  plug AuthorizeAction,
       {:credentials, :delete_credential, fallback: FallbackController}
       when action == :delete

  @accepted [
    :id,
    :name,
    :owner,
    :schema,
    :credential_bodies,
    :project_credentials
  ]

  @nothing_visible {"names nothing you can see", code: :not_found}

  @doc """
  Lists credentials with optional project filtering.

  This function has two variants:
  - With `project_id`: Returns all credentials for a specific project (regardless of owner)
  - Without `project_id`: Returns only credentials owned by the authenticated user

  Credential bodies are excluded from responses for security.

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map containing:
    - `project_id` - Project UUID (optional, filters to specific project)

  ## Returns

  - `200 OK` with list of credentials (bodies excluded)
  - `404 Not Found` if project doesn't exist (when project_id provided)
  - `403 Forbidden` if user lacks project access (when project_id provided)

  ## Examples

      # User's own credentials
      GET /api/credentials

      # All credentials for a project
      GET /api/credentials?project_id=a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, %{"project_id" => project_id}) do
    with {:ok, scope} <- Scope.fetch(conn.assigns.scope, project_id),
         :ok <-
           Permissions.permit(
             :project_users,
             :list_project_credentials,
             scope,
             scope.project
           ) do
      credentials =
        scope.project
        |> Credentials.list_credentials()
        |> hide_unseen_links(conn.assigns.scope)

      render(conn, "index.json", credentials: credentials)
    end
  end

  def index(conn, _params) do
    current_user = conn.assigns.current_resource

    with :ok <-
           Permissions.permit(
             :credentials,
             :list_credentials,
             conn.assigns.scope,
             nil
           ) do
      credentials =
        current_user
        |> Credentials.list_credentials()
        |> hide_unseen_links(conn.assigns.scope)

      render(conn, "index.json", credentials: credentials)
    end
  end

  @doc """
  Creates a new credential and optionally grants it access to projects.

  Creates a credential owned by the authenticated user. If project_credentials
  are specified, the user must have access to all listed projects. The credential
  body is included in the response only upon creation.

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map containing:
    - `name` - Credential name (required)
    - `body` - Credential JSON body with authentication details (required)
    - `project_credentials` - List of project associations (optional)

  ## Returns

  - `201 Created` with credential JSON including body
  - `400 Bad Request` (`malformed`) when the body isn't a JSON object
  - `422 Unprocessable Entity` on validation errors, with one entry for each
    project link the user may not make

  ## Examples

      # Create credential without project association
      POST /api/credentials
      {
        "name": "My API Key",
        "body": {"apiKey": "secret123"}
      }

      # Create credential with project associations
      POST /api/credentials
      {
        "name": "Shared Credential",
        "body": {"token": "abc123"},
        "project_credentials": [
          {"project_id": "a1b2c3d4-..."}
        ]
      }
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def create(conn, params) do
    scope = conn.assigns.scope
    owner = scope.actor

    with :ok <- PutBody.check_object(conn.body_params),
         {link_entries, project_ids} =
           check_links(params, [], {:ok, owner}, scope),
         :ok <- Errors.refuse(link_entries),
         {:ok, credential} <-
           Credentials.create_credential(
             Map.merge(params, %{
               "user_id" => owner.id,
               "project_credentials" =>
                 Enum.map(project_ids, &%{"project_id" => &1})
             }),
             owner
           ) do
      conn
      |> put_status(:created)
      |> render("create.json", credential: credential)
    end
  end

  @doc """
  Shows a credential, without its body, to a caller who may edit it.

  Links to projects whose credentials the caller may not list are left out.
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, %{"id" => id}) do
    with {:ok, id} <- PutBody.path_id(id),
         {:ok, credential} <- fetch_credential(id),
         :ok <-
           Permissions.permit(
             :credentials,
             :edit_credential,
             conn.assigns.scope,
             credential
           ) do
      render_credential(conn, credential)
    end
  end

  @doc """
  Creates the credential under the path's id, or replaces the name, schema and
  `main` body of the one that has it.

  Links are only ever added. A project the body lists gains a link, and a link
  the credential already holds stays even if the body leaves it out. The
  response leaves out links the caller may not see, as `show/2` does.

  The credential under the path's id is checked before the body: one the caller
  may not edit is `id_taken`, and one being deleted is `scheduled_for_deletion`.
  A refused body answers one 422 with every error in its keys, its owner and
  its links (error-format spec §9.6). The credential's own fields and its body
  are checked by `Lightning.Credentials` when it writes.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, %{"id" => id}) do
    scope = conn.assigns.scope
    body = conn.body_params

    with {:ok, id} <- PutBody.path_id(id),
         {:ok, target} <- update_target(id, scope),
         {:ok, naming} <- owner_naming(body["owner"], scope),
         {:ok, key_entries} <- PutBody.check(body, id, @accepted),
         {:ok, {owner, project_ids}} <-
           check_put_body(body, key_entries, naming, target, scope) do
      case target do
        :new -> create_under_id(conn, id, body, owner, project_ids)
        credential -> replace(conn, credential, body, owner, project_ids)
      end
    end
  end

  defp update_target(id, scope) do
    case Credentials.get_credential(id) do
      nil -> {:ok, :new}
      credential -> editable(credential, scope)
    end
  end

  defp editable(credential, scope) do
    case Permissions.permit(:credentials, :edit_credential, scope, credential) do
      :ok when credential.scheduled_deletion != nil ->
        {:error, :scheduled_for_deletion}

      :ok ->
        {:ok, credential}

      # The id belongs to a credential the caller can't write, which no body
      # can change (spec §4).
      {:error, :forbidden} ->
        {:error, :id_taken}

      error ->
        error
    end
  end

  # A caller who may name an owner has to name one. Anyone else owns the
  # credential and may name only themselves. Naming someone else is refused
  # before any lookup, so the reply never reveals whether an email has an
  # account.
  defp owner_naming(owner, scope) do
    case Permissions.permit(:credentials, :name_credential_owner, scope, nil) do
      :ok ->
        {:ok, :anyone}

      {:error, :forbidden} ->
        if names_someone_else?(owner, scope.actor),
          do: {:error, :forbidden},
          else: {:ok, :self}

      error ->
        error
    end
  end

  defp names_someone_else?(email, caller) when is_binary(email),
    do: String.downcase(email) != String.downcase(caller.email)

  defp names_someone_else?(_owner, _caller), do: false

  defp check_put_body(body, key_entries, naming, target, scope) do
    owner = resolve_owner(naming, body, scope.actor)
    held = held_project_ids(target)

    {link_entries, project_ids} = check_links(body, held, owner, scope)

    entries =
      key_entries ++
        body_entries(body) ++
        owner_entries(owner) ++ link_entries ++ link_key_entries(body)

    # Every refused owner has an entry, so it is refused with the rest.
    with :ok <- Errors.refuse(entries),
         {:ok, owner} <- owner,
         do: {:ok, {owner, project_ids}}
  end

  defp resolve_owner(:self, %{"owner" => owner}, _caller)
       when not is_binary(owner) and not is_nil(owner),
       do: {:error, [Errors.entry([:owner], {"is invalid", code: :type})]}

  defp resolve_owner(:self, _body, caller), do: {:ok, caller}

  defp resolve_owner(:anyone, %{"owner" => email}, _caller)
       when is_binary(email) do
    case Accounts.list_users_by_emails([email]) do
      [owner] ->
        {:ok, owner}

      _none ->
        {:error, [Errors.entry([:owner], @nothing_visible)]}
    end
  end

  defp resolve_owner(:anyone, %{"owner" => owner}, _caller)
       when not is_nil(owner),
       do: {:error, [Errors.entry([:owner], {"is invalid", code: :type})]}

  defp resolve_owner(:anyone, _body, _caller),
    do: {:error, [Errors.entry([:owner], {"can't be blank", code: :required})]}

  defp owner_entries({:ok, _owner}), do: []
  defp owner_entries({:error, entries}), do: entries

  @bodies_message "must be one body named main, holding an object"

  defp body_entries(%{
         "credential_bodies" => [%{"name" => "main", "body" => %{}} = main]
       })
       when map_size(main) == 2,
       do: []

  defp body_entries(_body),
    do: [Errors.entry([:credential_bodies], {@bodies_message, code: :one_body})]

  # A PUT link holds a project_id and nothing else.
  defp link_key_entries(%{"project_credentials" => links}) when is_list(links) do
    for {%{} = link, index} <- Enum.with_index(links),
        key <- link |> Map.keys() |> List.delete("project_id") |> Enum.sort(),
        do:
          Errors.entry(
            [:project_credentials, index, key],
            {"is not accepted", code: :unknown_key}
          )
  end

  defp link_key_entries(_body), do: []

  defp held_project_ids(:new), do: []

  defp held_project_ids(%Credential{} = credential) do
    credential
    |> Repo.preload(:project_credentials)
    |> Map.fetch!(:project_credentials)
    |> Enum.map(& &1.project_id)
  end

  # Checks each link the body asks for, at its position in the request (spec
  # §7 item 3): a project the caller can't see is `not_found`, and one the
  # caller may not link to, or whose owner isn't a member, is `no_access`
  # (plan D13). An owner the body failed to name is refused elsewhere, so its
  # membership isn't checked. Links already `held` are kept as they are.
  # Returns the entries and the ids of the projects to link.
  defp check_links(%{"project_credentials" => links}, held, owner, scope)
       when is_list(links) do
    shaped =
      links
      |> Enum.with_index()
      |> Enum.map(fn {link, index} -> {index, link_project_id(link, index)} end)

    ids = for {_index, {:ok, id}} <- shaped, id not in held, do: id
    scopes = Scope.fetch_all(scope, ids)
    unreachable = owner_unreachable(owner, ids)

    results =
      Enum.map(shaped, fn
        {index, {:ok, id}} ->
          cond do
            id in held ->
              :held

            refusal = link_refusal(scopes[id], id in unreachable) ->
              {:error, link_entry(index, refusal)}

            true ->
              {:ok, id}
          end

        {_index, error} ->
          error
      end)

    {for({:error, entry} <- results, do: entry),
     Enum.uniq(for {:ok, id} <- results, do: id)}
  end

  defp check_links(%{"project_credentials" => _links}, _held, _owner, _scope),
    do: {[Errors.entry([:project_credentials], {"is invalid", code: :type})], []}

  defp check_links(_body, _held, _owner, _scope), do: {[], []}

  defp link_project_id(%{"project_id" => id}, index) when is_binary(id) do
    case PutBody.path_id(id) do
      {:ok, id} -> {:ok, id}
      {:error, :not_found} -> {:error, link_entry(index, @nothing_visible)}
    end
  end

  defp link_project_id(%{"project_id" => nil}, index),
    do: {:error, link_entry(index, {"can't be blank", code: :required})}

  defp link_project_id(%{"project_id" => _id}, index),
    do: {:error, link_entry(index, {"is invalid", code: :type})}

  defp link_project_id(%{}, index),
    do: {:error, link_entry(index, {"can't be blank", code: :required})}

  defp link_project_id(_link, index),
    do:
      {:error,
       Errors.entry([:project_credentials, index], {"is invalid", code: :type})}

  defp link_entry(index, error),
    do: Errors.entry([:project_credentials, index, :project_id], error)

  defp link_refusal(nil, _owner_unreachable?), do: @nothing_visible

  defp link_refusal(project_scope, owner_unreachable?) do
    cond do
      not Scope.has_standing?(project_scope) ->
        @nothing_visible

      not ProjectUsers.permitted?(:create_project_credential, project_scope) ->
        {"you may not link a credential to this project", code: :no_access}

      owner_unreachable? ->
        {"the credential's owner is not a member of this project",
         code: :no_access}

      true ->
        nil
    end
  end

  defp owner_unreachable({:error, _entries}, _project_ids), do: []

  defp owner_unreachable({:ok, owner}, project_ids) do
    owner.id
    |> Credentials.projects_without_access(Enum.uniq(project_ids))
    |> Enum.map(& &1.id)
  end

  defp create_under_id(conn, id, body, owner, project_ids) do
    body
    |> credential_params()
    |> Map.merge(%{
      "user_id" => owner.id,
      "project_credentials" => Enum.map(project_ids, &%{"project_id" => &1})
    })
    |> Credentials.create_credential(conn.assigns.current_resource, id: id)
    |> case do
      {:ok, credential} ->
        conn |> put_status(:created) |> render_credential(credential)

      # Someone else created it since the lookup. Rerun the request so the
      # caller is checked against that credential.
      {:error, %Ecto.Changeset{} = changeset} ->
        if PutBody.id_taken?(changeset),
          do: update(conn, %{"id" => id}),
          else: {:error, changeset}

      error ->
        error
    end
  end

  # Lightning never moves a credential to another owner. The links the
  # credential holds go to `update_credential` with their ids, so its
  # `cast_assoc` keeps them rather than replacing them.
  defp replace(conn, credential, body, owner, project_ids) do
    if credential.user_id == owner.id do
      credential = Repo.preload(credential, :project_credentials)

      links =
        Enum.map(
          credential.project_credentials,
          &%{"id" => &1.id, "project_id" => &1.project_id}
        ) ++ Enum.map(project_ids, &%{"project_id" => &1})

      params =
        body |> credential_params() |> Map.put("project_credentials", links)

      with {:ok, credential} <-
             Credentials.update_credential(
               credential,
               params,
               conn.assigns.current_resource
             ),
           do: render_credential(conn, credential)
    else
      {:error, :id_taken}
    end
  end

  defp credential_params(body) do
    body
    |> Map.take(["schema"])
    |> Map.merge(%{
      "name" => body["name"],
      "credential_bodies" => body["credential_bodies"]
    })
  end

  defp fetch_credential(id) do
    case Credentials.get_credential(id) do
      nil -> {:error, :not_found}
      credential -> {:ok, credential}
    end
  end

  defp permitted_ids(scopes, action) do
    for {id, project_scope} <- scopes,
        ProjectUsers.permitted?(action, project_scope),
        into: MapSet.new(),
        do: id
  end

  defp render_credential(conn, credential) do
    [credential] =
      [Repo.preload(credential, [:project_credentials, :projects])]
      |> hide_unseen_links(conn.assigns.scope)

    render(conn, "create.json", credential: credential)
  end

  # A credential can be linked to projects the caller has no standing in,
  # because its owner lost access or because a list holds someone else's
  # credentials. Those links are left out. Naming a project also needs
  # `:access_project`, so a service account without `projects:write` sees every
  # link but no project names.
  defp hide_unseen_links(credentials, scope) do
    scopes =
      Scope.fetch_all(
        scope,
        credentials
        |> Enum.flat_map(& &1.project_credentials)
        |> Enum.map(& &1.project_id)
        |> Enum.uniq()
      )

    shown = permitted_ids(scopes, :list_project_credentials)
    named = permitted_ids(scopes, :access_project)

    Enum.map(credentials, fn credential ->
      %{
        credential
        | projects: Enum.filter(credential.projects, &(&1.id in named)),
          project_credentials:
            Enum.filter(
              credential.project_credentials,
              &(&1.project_id in shown)
            )
      }
    end)
  end

  @doc """
  Deletes a credential owned by the authenticated user.

  Permanently removes a credential. Only the credential owner can delete it.

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map containing:
    - `id` - Credential UUID (required)

  ## Returns

  - `204 No Content` on successful deletion
  - `404 Not Found` if credential doesn't exist or invalid UUID
  - `403 Forbidden` if user is not the credential owner

  ## Examples

      DELETE /api/credentials/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def delete(conn, %{"id" => id}) do
    with {:ok, id} <- PutBody.path_id(id),
         {:ok, credential} <- fetch_credential(id),
         :ok <-
           Permissions.permit(
             :credentials,
             :delete_credential,
             conn.assigns.scope,
             credential
           ),
         {:ok, _deleted} <-
           Credentials.delete_credential(
             credential,
             conn.assigns.current_resource
           ) do
      send_resp(conn, :no_content, "")
    end
  end
end
