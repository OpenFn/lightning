defmodule LightningWeb.API.KeychainCredentialController do
  @moduledoc """
  A project's keychain credentials, which pick one of the project's
  credentials for each run by reading a JSONPath from its input.

      GET /api/projects/:project_id/keychain_credentials
      PUT /api/projects/:project_id/keychain_credentials/:id
        {"name": "Per-district", "path": "$.district", "default_credential_id": "…"}
      DELETE /api/projects/:project_id/keychain_credentials/:id

  Any member may list them. Writing needs an owner or admin, or a support user
  where the project allows support access, or the service account. A keychain
  credential records the person who created it, so the service account may
  replace and delete one but not create one.
  """
  use LightningWeb, :controller

  alias Lightning.Credentials
  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Projects.Project
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction,
       {:project_users, :list_project_credentials}
       when action == :index

  plug AuthorizeAction,
       {:credentials, :edit_keychain_credential}
       when action == :update

  plug AuthorizeAction,
       {:credentials, :delete_keychain_credential}
       when action == :delete

  @accepted [:id, :name, :path, :default_credential_id]
  @edit {:credentials, :edit_keychain_credential}

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, params) do
    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             {:project_users, :list_project_credentials}
           ) do
      page =
        Credentials.paginate_keychain_credentials_for_project(
          project,
          Filters.page(params)
        )

      render(conn, :index, page: page, filters: %{})
    end
  end

  @doc """
  Creates the keychain credential under the path's id in the project, or
  replaces the name, path and default credential of the project's keychain
  credential that has it. A default credential left out of a replace is
  cleared.

  An id held by another project's keychain credential answers 409 `id_taken`
  to anyone who may create one in the path's project. A refused body answers
  one 422 with its keys and the keychain credential's fields together.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, _params) do
    scope = conn.assigns.scope
    body = conn.body_params

    with {:ok, project} <-
           Target.project(scope, Request.param(conn, "project_id"), @edit),
         {:ok, id} <- Request.id(Request.param(conn, "id")),
         {:ok, target} <- update_target(id, project, scope),
         {:ok, entries} <- Request.check(body, id, @accepted) do
      attrs = Map.new(@accepted -- [:id], &{to_string(&1), body[to_string(&1)]})

      case target do
        :new -> create(conn, project, id, attrs, entries)
        keychain -> replace(conn, keychain, attrs, entries)
      end
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def delete(conn, _params) do
    with {:ok, keychain} <-
           Target.in_project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             {:credentials, :delete_keychain_credential},
             Request.param(conn, "id"),
             &Credentials.get_keychain_credential_for_project/2
           ),
         {:ok, _deleted} <-
           Credentials.delete_keychain_credential(
             keychain,
             conn.assigns.current_resource
           ) do
      send_resp(conn, :no_content, "")
    end
  end

  # A free id, or one held in another project, would be a create, so both ask
  # whether the caller may create one here first.
  defp update_target(id, %Project{id: project_id} = project, scope) do
    case Credentials.get_keychain_credential(id) do
      %KeychainCredential{project_id: ^project_id} = keychain ->
        {:ok, keychain}

      found ->
        with {:ok, _project} <-
               Target.project(
                 scope,
                 project,
                 {:credentials, :create_keychain_credential}
               ) do
          if found, do: {:error, :id_taken}, else: {:ok, :new}
        end
    end
  end

  defp create(conn, project, id, attrs, entries) do
    actor = conn.assigns.current_resource
    keychain = %{Credentials.new_keychain_credential(actor, project) | id: id}

    with :ok <-
           Errors.refuse(
             entries ++
               Errors.from_changeset(
                 Credentials.change_keychain_credential(keychain, attrs)
               )
           ) do
      case Credentials.create_keychain_credential(keychain, attrs, actor) do
        {:ok, keychain} ->
          conn |> put_status(:created) |> render_keychain(keychain)

        # Someone else created it since the lookup. Rerun the request so it
        # meets that keychain credential.
        {:error, %Ecto.Changeset{} = changeset} ->
          if Request.id_taken?(changeset),
            do: update(conn, conn.params),
            else: {:error, changeset}

        error ->
          error
      end
    end
  end

  defp replace(conn, keychain, attrs, entries) do
    changeset = Credentials.change_keychain_credential(keychain, attrs)

    with :ok <- Errors.refuse(entries ++ Errors.from_changeset(changeset)),
         {:ok, keychain} <-
           Credentials.update_keychain_credential(
             keychain,
             attrs,
             conn.assigns.current_resource
           ) do
      render_keychain(conn, keychain)
    end
  end

  # Read back with who created it and its default credential. Another
  # request may have deleted it since the write.
  defp render_keychain(conn, keychain) do
    case Credentials.get_keychain_credential_for_project(
           keychain.project_id,
           keychain.id
         ) do
      {:ok, keychain} -> render(conn, :show, keychain_credential: keychain)
      {:error, :not_found} -> {:error, :concurrent_edit}
    end
  end
end
