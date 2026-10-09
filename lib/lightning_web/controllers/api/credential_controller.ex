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
  alias Lightning.Accounts.User
  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects
  alias Lightning.Repo
  alias Lightning.ServiceAccount
  alias LightningWeb.API.PutRequest

  action_fallback LightningWeb.FallbackController

  # `require_authenticated_api_resource` lets repo-connection tokens through,
  # and a credential belongs to a person. Every action would hand a machine
  # token to a function that only takes a user or a service account, which
  # raises rather than refusing. Answer it once here. Only `show` and `update`
  # sit behind the credentials scope a service account's token is held to.
  plug :require_person_or_service_account

  defp require_person_or_service_account(conn, _opts) do
    case {conn.assigns.current_resource, action_name(conn)} do
      {%User{}, _action} ->
        conn

      {%ServiceAccount{}, action} when action in [:show, :update] ->
        conn

      _other ->
        conn
        |> put_status(:forbidden)
        |> put_view(LightningWeb.ErrorView)
        |> render(:"403")
        |> halt()
    end
  end

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
    current_user = conn.assigns.current_resource

    with project when not is_nil(project) <- Projects.get_project(project_id),
         :ok <-
           ProjectUsers
           |> Permissions.can(
             :access_project,
             current_user,
             project
           ) do
      # The requested project is already access-checked above, so always show
      # it (covers membership at any depth and support-user access).
      credentials =
        project
        |> Credentials.list_credentials()
        |> scope_to_visible_projects(current_user, [project.id])

      render(conn, "index.json", credentials: credentials)
    else
      nil ->
        {:error, :not_found}

      {:error, :unauthorized} ->
        {:error, :forbidden}
    end
  end

  def index(conn, _params) do
    current_user = conn.assigns.current_resource

    credentials =
      current_user
      |> Credentials.list_credentials()
      |> scope_to_visible_projects(current_user)

    render(conn, "index.json", credentials: credentials)
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

    with {:ok, validated_params} <-
           validate_and_authorize_projects(params, current_user),
         {:ok, credential} <-
           Credentials.create_credential(validated_params, current_user) do
      conn
      |> put_status(:created)
      |> render("create.json", credential: credential)
    end
  end

  @doc """
  Shows a credential, never its body: to its owner, or to a service account
  holding the credentials scope.
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, %{"id" => id}) do
    actor = conn.assigns.current_resource

    with {:ok, id} <- PutRequest.cast_uuid(id),
         %Credential{} = credential <- Credentials.get_credential(id),
         :ok <- authorize_owner(actor, credential) do
      render_credential(conn, credential, actor)
    else
      :error -> {:error, :not_found}
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  Creates the credential under the path's id, or replaces the name, schema and
  `main` body of the one that has it.

  Links are only added: a project the body lists gains one, and a link the
  credential already holds is kept whether or not the body lists it.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, %{"id" => id}) do
    actor = conn.assigns.current_resource

    with {:ok, attrs} <- parse_body(conn.body_params, id),
         {:ok, owner} <- resolve_owner(attrs, actor) do
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
          else: [
            project_credentials: "must each be an object holding a project_id"
          ]
      end)
      |> PutRequest.attrs()
    end
  end

  defp main_body_only?([%{"name" => "main", "body" => %{}} = body]),
    do: map_size(body) == 2

  defp main_body_only?(_bodies), do: false

  defp project_link?(%{"project_id" => project_id} = link)
       when map_size(link) == 1 and is_binary(project_id),
       do: PutRequest.cast_uuid(project_id) != :error

  defp project_link?(_link), do: false

  # A person's token makes the caller the owner, and may only name the caller:
  # naming anyone else is refused before the lookup, so the answer never says
  # whether an email has an account. A service account must name the owner.
  defp resolve_owner(%{owner: email}, %User{} = user) do
    if String.downcase(email) == String.downcase(user.email),
      do: {:ok, user},
      else: {:error, :forbidden}
  end

  defp resolve_owner(_attrs, %User{} = user), do: {:ok, user}

  defp resolve_owner(%{owner: email}, %ServiceAccount{}) do
    case Accounts.list_users_by_emails([email]) do
      [owner] -> {:ok, owner}
      _none -> {:error, :invalid, %{owner: ["no user has this email"]}}
    end
  end

  defp resolve_owner(_attrs, %ServiceAccount{}),
    do: {:error, :invalid, %{owner: ["can't be blank"]}}

  defp create_under_id(conn, attrs, owner, actor) do
    project_ids = requested_project_ids(attrs)

    with :ok <- authorize_links(project_ids, actor) do
      attrs
      |> credential_params()
      |> Map.merge(%{
        "user_id" => owner.id,
        "project_credentials" => Enum.map(project_ids, &%{"project_id" => &1})
      })
      |> Credentials.create_credential(actor, id: attrs.id)
      |> case do
        {:ok, credential} ->
          conn |> put_status(:created) |> render_credential(credential, actor)

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

  # A person keeps their answer; only apply, through a service account, is
  # told the credential is about to be deleted.
  defp replace(
         _conn,
         %Credential{user_id: owner_id, scheduled_deletion: %DateTime{}},
         _attrs,
         %User{id: owner_id},
         %ServiceAccount{}
       ),
       do: {:error, :scheduled_for_deletion}

  # The links the credential holds go to `update_credential` with their ids, so
  # its `cast_assoc` keeps them rather than replacing them.
  defp replace(
         conn,
         %Credential{user_id: owner_id} = credential,
         attrs,
         %User{id: owner_id},
         actor
       ) do
    credential = Repo.preload(credential, :project_credentials)
    held = credential.project_credentials
    new_ids = requested_project_ids(attrs) -- Enum.map(held, & &1.project_id)

    with :ok <- authorize_links(new_ids, actor) do
      links =
        Enum.map(held, &%{"id" => &1.id, "project_id" => &1.project_id}) ++
          Enum.map(new_ids, &%{"project_id" => &1})

      params =
        attrs |> credential_params() |> Map.put("project_credentials", links)

      case Credentials.update_credential(credential, params, actor) do
        {:ok, credential} -> render_credential(conn, credential, actor)
        error -> render_write_error(conn, error)
      end
    end
  end

  # Lightning never moves a credential to another owner to make a write fit.
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

  defp authorize_links(project_ids, actor) do
    if Enum.all?(project_ids, &can_link?(&1, actor)),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp can_link?(project_id, actor) do
    case Projects.get_project(project_id) do
      nil ->
        false

      project ->
        Permissions.can?(
          ProjectUsers,
          :create_project_credential,
          actor,
          project
        )
    end
  end

  defp authorize_owner(actor, credential) do
    if Permissions.can?(:credentials, :edit_credential, actor, credential),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp render_write_error(conn, {:error, %Ecto.Changeset{} = changeset}) do
    # The owner already holds this name under another id.
    if PutRequest.unique_error?(changeset, :name),
      do: {:error, :name_taken},
      else: PutRequest.render_errors(conn, PutRequest.flat_errors(changeset))
  end

  defp render_write_error(_conn, {:error, :unauthorized}),
    do: {:error, :forbidden}

  # What remains is an OAuth token body the context refused.
  defp render_write_error(conn, {:error, _reason}),
    do: PutRequest.render_errors(conn, %{credential_bodies: ["is invalid"]})

  # Every link is listed, since the caller needs each link's id; a person sees
  # only the projects they belong to by name.
  defp render_credential(conn, credential, actor) do
    credential =
      credential
      |> Repo.preload([:project_credentials, :projects])
      |> hide_unseen_projects(actor)

    render(conn, "create.json", credential: credential)
  end

  defp hide_unseen_projects(credential, %User{} = user) do
    visible = user |> Projects.member_project_ids() |> MapSet.new()

    %{
      credential
      | projects: Enum.filter(credential.projects, &(&1.id in visible))
    }
  end

  defp hide_unseen_projects(credential, %ServiceAccount{}), do: credential

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
         :ok <- validate_credential_ownership(credential, current_user),
         {:ok, _} <- Credentials.delete_credential(credential, current_user) do
      send_resp(conn, :no_content, "")
    else
      :error ->
        {:error, :not_found}

      nil ->
        {:error, :not_found}

      {:error, :forbidden} ->
        {:error, :forbidden}

      error ->
        error
    end
  end

  # A shared credential may be linked to projects in other tenants; rendering
  # those would leak their id/name/description across the tenant boundary. Prune
  # each credential's project associations to the caller-visible set here so the
  # JSON view can render whatever it is handed.
  #
  # The visible set is the caller's memberships (any depth), matching the
  # :access_project check so a caller's own sandbox associations are not
  # dropped, plus any `extra_project_ids` already access-checked by the caller
  # (e.g. the requested project on the project-scoped endpoint).
  defp scope_to_visible_projects(
         credentials,
         current_user,
         extra_project_ids \\ []
       ) do
    visible =
      current_user
      |> Projects.member_project_ids()
      |> Enum.concat(extra_project_ids)
      |> MapSet.new()

    Enum.map(credentials, fn credential ->
      projects =
        filter_accessible_projects(
          credential.projects,
          visible,
          fn project -> project.id end
        )

      project_credentials =
        filter_accessible_projects(
          credential.project_credentials,
          visible,
          fn project_credential -> project_credential.project_id end
        )

      %{
        credential
        | projects: projects,
          project_credentials: project_credentials
      }
    end)
  end

  defp filter_accessible_projects(assoc, visible, key_fun) when is_list(assoc) do
    Enum.filter(assoc, fn record -> MapSet.member?(visible, key_fun.(record)) end)
  end

  # Leave unloaded associations untouched; the view renders them as [].
  defp filter_accessible_projects(assoc, _visible, _key_fun), do: assoc

  defp validate_credential_ownership(credential, current_user) do
    if credential.user_id == current_user.id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp validate_and_authorize_projects(params, current_user) do
    # Ensure user_id is set to the current authenticated user
    params_with_user = Map.put(params, "user_id", current_user.id)

    project_ids =
      params
      |> Map.get("project_credentials", [])
      |> Enum.map(&Map.get(&1, "project_id"))
      |> Enum.filter(& &1)

    with :ok <- authorize_links(project_ids, current_user),
         do: {:ok, params_with_user}
  end
end
