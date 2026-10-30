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
  alias Lightning.Scope
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  # Both index routes need the `credentials:write` grant, and that is all this
  # plug checks.
  plug AuthorizeAction,
       {:credentials, :list_credentials}
       when action == :index

  plug AuthorizeAction,
       {:credentials, :create_credential}
       when action == :create

  plug AuthorizeAction,
       {:credentials, :edit_credential}
       when action in [:show, :update]

  plug AuthorizeAction,
       {:credentials, :delete_credential}
       when action == :delete

  @accepted [
    :id,
    :name,
    :owner,
    :schema,
    :credential_bodies,
    :project_credentials
  ]

  @doc """
  Lists credentials, without their bodies.

  With `project_id`, lists every credential linked to that project, whoever
  owns it. A project the caller may not see answers 403 `forbidden`. Without
  `project_id`, lists the caller's own credentials.

  ## Examples

      # User's own credentials
      GET /api/credentials

      # All credentials for a project
      GET /api/credentials?project_id=a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, %{"project_id" => _}) do
    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             {:project_users, :list_project_credentials}
           ) do
      credentials =
        project
        |> Credentials.list_credentials()
        |> hide_unseen_links(conn.assigns.scope)

      render(conn, "index.json", credentials: credentials)
    end
  end

  def index(conn, _params) do
    scope = conn.assigns.scope

    with :ok <- Permissions.permit(:credentials, :list_credentials, scope, nil) do
      credentials =
        scope.actor
        |> Credentials.list_credentials()
        |> hide_unseen_links(scope)

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
  - `403 Forbidden` to a caller that can't own a credential, such as the
    service account
  - `400 Bad Request` (`malformed`) when the body isn't a JSON object
  - `503 Service Unavailable` (`not_ready`) while the adaptor catalogue can't
    answer for the body's schema, whatever else is wrong with the body
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

    with :ok <-
           Permissions.permit(
             :credentials,
             :create_credential,
             scope,
             %Credential{user_id: owner.id}
           ),
         :ok <- Request.check_object(conn.body_params),
         :ok <- Credentials.check_catalogue(params["schema"]),
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
  Shows a credential, without its body, to a caller who may edit it or who
  sees it linked to a project whose credentials it may list. Anyone else hears
  403 `forbidden`, whether or not the credential exists.

  Only the service account may read every credential, so only it hears 404
  `not_found` for an id that names none, and 400 `invalid_parameter` for one
  that isn't a UUID. Everyone else hears 403 for both.

  Links to projects whose credentials the caller may not list are left out.
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, _params) do
    with {:ok, credential} <-
           Target.record(
             conn.assigns.scope,
             Request.param(conn, "id"),
             {:credentials, :see_credential},
             &fetch_credential/1
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

  The path names the credential, so an id already in use is an update. It is
  checked before the body: one the caller may not edit is 403 `forbidden`, even
  when the caller can see it, and one being deleted is
  `scheduled_for_deletion`. An id that isn't a UUID is 400 `invalid_parameter`
  to anyone, since anyone holding the grant may create a credential.

  A refused body answers one 422 with every error in its keys, its owner and
  its links, unless the adaptor catalogue can't yet answer for the schema the
  credential would have, which is 503 `not_ready`. The credential's own fields
  and its body are checked by `Lightning.Credentials` when it writes. A body
  naming an owner other than an existing credential's is 422 `not_allowed` at
  the owner, since the owner applies only on create.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, _params) do
    scope = conn.assigns.scope
    body = conn.body_params

    with {:ok, id} <- Request.id(Request.param(conn, "id")),
         {:ok, target} <- update_target(id, scope),
         {:ok, naming} <- owner_naming(body["owner"], scope),
         {:ok, key_entries} <- Request.check(body, id, @accepted),
         :ok <- Credentials.check_catalogue(schema(body, target)),
         {:ok, {owner, project_ids}} <-
           check_put_body(body, key_entries, naming, target, scope) do
      case target do
        :new -> create_under_id(conn, id, body, owner, project_ids)
        credential -> replace(conn, credential, body, owner, project_ids)
      end
    end
  end

  # A replace that leaves out the schema keeps the credential's.
  defp schema(%{"schema" => schema}, _target), do: schema
  defp schema(_body, :new), do: nil
  defp schema(_body, credential), do: credential.schema

  defp update_target(id, scope) do
    case Credentials.get_credential(id) do
      nil -> {:ok, :new}
      credential -> editable(credential, scope)
    end
  end

  defp editable(credential, scope) do
    with :ok <-
           Permissions.permit(:credentials, :edit_credential, scope, credential),
         do: {:ok, Credentials.preload_links(credential)}
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

  defp resolve_owner(_naming, %{"owner" => owner}, _caller)
       when not is_binary(owner) and not is_nil(owner),
       do: {:error, [Errors.entry([:owner], {"is invalid", code: :type})]}

  defp resolve_owner(:self, _body, caller), do: {:ok, caller}

  defp resolve_owner(:anyone, %{"owner" => email}, _caller)
       when is_binary(email) do
    case Accounts.list_users_by_emails([email]) do
      [owner] ->
        {:ok, owner}

      _none ->
        {:error, [Errors.entry([:owner], Errors.not_visible())]}
    end
  end

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
        entry <-
          Request.unknown_keys(link, [:project_credentials, index], [:project_id]),
        do: entry
  end

  defp link_key_entries(_body), do: []

  defp held_project_ids(:new), do: []

  defp held_project_ids(%Credential{project_credentials: links}),
    do: Enum.map(links, & &1.project_id)

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
    case Request.id({[:project_credentials, index, :project_id], id}) do
      {:ok, id} ->
        {:ok, id}

      {:error, {:invalid_id, _}} ->
        {:error, link_entry(index, Errors.not_visible())}
    end
  end

  defp link_project_id(%{"project_id" => id}, index) when not is_nil(id),
    do: {:error, link_entry(index, {"is invalid", code: :type})}

  defp link_project_id(%{}, index),
    do: {:error, link_entry(index, {"can't be blank", code: :required})}

  defp link_project_id(_link, index),
    do:
      {:error,
       Errors.entry([:project_credentials, index], {"is invalid", code: :type})}

  defp link_entry(index, error),
    do: Errors.entry([:project_credentials, index, :project_id], error)

  # A link's entry codes follow spec §7 item 3 and plan D13.
  defp link_refusal(nil, _owner_unreachable?), do: Errors.not_visible()

  defp link_refusal(project_scope, owner_unreachable?) do
    case ProjectUsers.authorize(
           :create_project_credential,
           project_scope,
           project_scope.project
         ) do
      {:error, :no_standing} ->
        Errors.not_visible()

      true when owner_unreachable? ->
        {"the credential's owner is not a member of this project",
         code: :no_access}

      true ->
        nil

      _refused ->
        {"you may not link a credential to this project", code: :no_access}
    end
  end

  # An owner the body failed to name already has its own entry, so its
  # membership isn't checked.
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
        if Request.id_taken?(changeset),
          do: update(conn, conn.params),
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
      Errors.refuse([
        Errors.entry(
          [:owner],
          {"can't change when replacing a credential", code: :not_allowed}
        )
      ])
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
      credential -> {:ok, Credentials.preload_links(credential)}
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
      [Credentials.preload_links_and_projects(credential)]
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
  - `403 Forbidden` if the caller doesn't own it, whether or not it exists or
    the id is a UUID

  ## Examples

      DELETE /api/credentials/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def delete(conn, _params) do
    scope = conn.assigns.scope

    with {:ok, credential} <-
           Target.record(
             scope,
             Request.param(conn, "id"),
             {:credentials, :delete_credential},
             &fetch_credential/1
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
