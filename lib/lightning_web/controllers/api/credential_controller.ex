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

  import Ecto.Changeset

  alias Lightning.Accounts
  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Repo
  alias Lightning.Scope
  alias LightningWeb.API.PutRequest
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback LightningWeb.FallbackController

  # Both index routes need the `credentials:write` grant, and that is all this
  # plug checks.
  plug AuthorizeAction, {:credentials, :list_credentials} when action == :index

  plug AuthorizeAction,
       {:credentials, :edit_credential}
       when action in [:create, :show, :update]

  plug AuthorizeAction, {:credentials, :delete_credential} when action == :delete

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
  - `422 Unprocessable Entity` on validation errors
  - `403 Forbidden` if user lacks access to specified projects

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
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    current_user = conn.assigns.current_resource

    with :ok <- validate_links(params),
         {:ok, validated_params} <-
           validate_and_authorize_projects(params, conn.assigns.scope),
         {:ok, credential} <-
           Credentials.create_credential(validated_params, current_user) do
      conn
      |> put_status(:created)
      |> render("create.json", credential: credential)
    else
      {:error, :invalid, errors} -> PutRequest.render_errors(conn, errors)
      error -> error
    end
  end

  @doc """
  Shows a credential, without its body, to a caller who may edit it.

  Links to projects whose credentials the caller may not list are left out.
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, %{"id" => id}) do
    with {:ok, id} <- PutRequest.cast_uuid(id),
         %Credential{} = credential <- Credentials.get_credential(id),
         :ok <-
           Permissions.permit(
             :credentials,
             :edit_credential,
             conn.assigns.scope,
             credential
           ) do
      render_credential(conn, credential)
    else
      :error -> {:error, :not_found}
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  Creates the credential under the path's id, or replaces the name, schema and
  `main` body of the one that has it.

  Links are only ever added. A project the body lists gains a link, and a link
  the credential already holds stays even if the body leaves it out. The
  response leaves out links the caller may not see, as `show/2` does.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, %{"id" => id}) do
    actor = conn.assigns.current_resource

    with {:ok, attrs} <- parse_body(conn.body_params, id),
         {:ok, owner} <- resolve_owner(attrs, conn.assigns.scope) do
      case Credentials.get_credential(attrs.id) do
        nil -> create_under_id(conn, attrs, owner, actor)
        credential -> replace(conn, credential, attrs, owner, actor)
      end
    else
      {:error, :invalid, errors} -> PutRequest.render_errors(conn, errors)
      error -> error
    end
  end

  @body_types %{
    id: :binary_id,
    name: :string,
    owner: :string,
    schema: :string,
    credential_bodies: {:array, :map},
    project_credentials: {:array, :map}
  }

  @bodies_message "must be one body named main, holding an object"
  @links_message "must each be an object holding a project_id"

  defp parse_body(body, id) do
    with {:ok, changeset} <- PutRequest.changeset(body, id, {%{}, @body_types}) do
      changeset
      |> validate_required(:credential_bodies, message: @bodies_message)
      |> validate_change(:credential_bodies, fn :credential_bodies, bodies ->
        if main_body_only?(bodies),
          do: [],
          else: [credential_bodies: @bodies_message]
      end)
      |> validate_change(:project_credentials, fn :project_credentials, links ->
        if Enum.all?(links, &project_link?/1),
          do: [],
          else: [project_credentials: @links_message]
      end)
      |> PutRequest.attrs()
    end
  end

  defp main_body_only?([%{"name" => "main", "body" => %{}} = body]),
    do: map_size(body) == 2

  defp main_body_only?(_bodies), do: false

  defp project_link?(link) when map_size(link) == 1, do: names_a_project?(link)
  defp project_link?(_link), do: false

  defp names_a_project?(%{"project_id" => project_id})
       when is_binary(project_id),
       do: PutRequest.cast_uuid(project_id) != :error

  defp names_a_project?(_link), do: false

  defp validate_links(%{"project_credentials" => links}) when is_list(links) do
    if Enum.all?(links, &names_a_project?/1),
      do: :ok,
      else: {:error, :invalid, %{project_credentials: [@links_message]}}
  end

  defp validate_links(%{"project_credentials" => _links}),
    do: {:error, :invalid, %{project_credentials: [@links_message]}}

  defp validate_links(_params), do: :ok

  # A caller who may name an owner has to name one. Anyone else owns the
  # credential and may name only themselves. Naming someone else is refused
  # before any lookup, so the reply never reveals whether an email has an
  # account.
  defp resolve_owner(attrs, scope) do
    case Permissions.permit(:credentials, :name_credential_owner, scope, nil) do
      :ok -> look_up_owner(attrs)
      {:error, :forbidden} -> own_email_only(attrs, scope.actor)
      error -> error
    end
  end

  defp look_up_owner(%{owner: email}) do
    case Accounts.list_users_by_emails([email]) do
      [owner] -> {:ok, owner}
      _none -> {:error, :invalid, %{owner: ["no user has this email"]}}
    end
  end

  defp look_up_owner(_attrs),
    do: {:error, :invalid, %{owner: ["can't be blank"]}}

  defp own_email_only(%{owner: email}, caller) do
    if String.downcase(email) == String.downcase(caller.email),
      do: {:ok, caller},
      else: {:error, :forbidden}
  end

  defp own_email_only(_attrs, caller), do: {:ok, caller}

  defp create_under_id(conn, attrs, owner, actor) do
    project_ids = requested_project_ids(attrs)

    with :ok <- authorize_links(project_ids, conn.assigns.scope) do
      attrs
      |> credential_params()
      |> Map.merge(%{
        "user_id" => owner.id,
        "project_credentials" => Enum.map(project_ids, &%{"project_id" => &1})
      })
      |> Credentials.create_credential(actor, id: attrs.id)
      |> case do
        {:ok, credential} ->
          conn |> put_status(:created) |> render_credential(credential)

        {:error, %Ecto.Changeset{} = changeset} ->
          if PutRequest.unique_error?(changeset, :id),
            do:
              replace(
                conn,
                Credentials.get_credential(attrs.id),
                attrs,
                owner,
                actor
              ),
            else: render_write_error(conn, {:error, changeset})

        error ->
          render_write_error(conn, error)
      end
    end
  end

  # The links the credential holds go to `update_credential` with their ids, so
  # its `cast_assoc` keeps them rather than replacing them.
  defp replace(
         conn,
         %Credential{user_id: owner_id} = credential,
         attrs,
         %{id: owner_id},
         actor
       ) do
    credential = Repo.preload(credential, :project_credentials)
    held = credential.project_credentials
    new_ids = requested_project_ids(attrs) -- Enum.map(held, & &1.project_id)

    with :ok <- authorize_links(new_ids, conn.assigns.scope) do
      links =
        Enum.map(held, &%{"id" => &1.id, "project_id" => &1.project_id}) ++
          Enum.map(new_ids, &%{"project_id" => &1})

      params =
        attrs |> credential_params() |> Map.put("project_credentials", links)

      case Credentials.update_credential(credential, params, actor) do
        {:ok, credential} -> render_credential(conn, credential)
        error -> render_write_error(conn, error)
      end
    end
  end

  # Lightning never moves a credential to another owner.
  defp replace(_conn, _credential, _attrs, _owner, _actor),
    do: {:error, :id_taken}

  defp credential_params(attrs) do
    %{"name" => attrs[:name], "credential_bodies" => attrs.credential_bodies}
    |> then(fn params ->
      if Map.has_key?(attrs, :schema),
        do: Map.put(params, "schema", attrs.schema),
        else: params
    end)
  end

  defp requested_project_ids(attrs) do
    attrs
    |> Map.get(:project_credentials, [])
    |> Enum.map(&Ecto.UUID.cast!(&1["project_id"]))
    |> Enum.uniq()
  end

  defp authorize_links(project_ids, scope) do
    linkable =
      scope
      |> Scope.fetch_all(project_ids)
      |> permitted_ids(:create_project_credential)

    if Enum.all?(project_ids, &linkable?(&1, linkable)),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp linkable?(project_id, linkable) do
    case Ecto.UUID.cast(project_id) do
      {:ok, id} -> id in linkable
      :error -> false
    end
  end

  defp permitted_ids(scopes, action) do
    for {id, project_scope} <- scopes,
        ProjectUsers.permitted?(action, project_scope),
        into: MapSet.new(),
        do: id
  end

  defp render_write_error(conn, {:error, %Ecto.Changeset{} = changeset}) do
    # The owner already holds this name under another id.
    if PutRequest.unique_error?(changeset, :name),
      do: {:error, :name_taken},
      else: PutRequest.render_errors(conn, PutRequest.flat_errors(changeset))
  end

  defp render_write_error(_conn, {:error, :unauthorized}),
    do: {:error, :forbidden}

  defp render_write_error(_conn, {:error, reason} = error)
       when reason in [:insufficient_scope, :scheduled_for_deletion],
       do: error

  # What remains is an OAuth token body the context refused.
  defp render_write_error(conn, {:error, _reason}),
    do: PutRequest.render_errors(conn, %{credential_bodies: ["is invalid"]})

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
  Credentials in use by workflows cannot be deleted and will return an error.

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
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => id}) do
    current_user = conn.assigns.current_resource

    with {:ok, id} <- PutRequest.cast_uuid(id),
         credential when not is_nil(credential) <-
           Credentials.get_credential(id),
         {:ok, _} <- Credentials.delete_credential(credential, current_user) do
      send_resp(conn, :no_content, "")
    else
      :error ->
        {:error, :not_found}

      nil ->
        {:error, :not_found}

      {:error, :unauthorized} ->
        {:error, :forbidden}

      error ->
        error
    end
  end

  defp validate_and_authorize_projects(params, scope) do
    # Ensure user_id is set to the current authenticated user
    params_with_user = Map.put(params, "user_id", scope.actor.id)

    project_ids =
      params
      |> Map.get("project_credentials", [])
      |> Enum.map(&Map.get(&1, "project_id"))

    with :ok <- authorize_links(project_ids, scope),
         do: {:ok, params_with_user}
  end
end
