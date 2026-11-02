defmodule LightningWeb.API.ProjectCredentialController do
  @moduledoc """
  Links a credential to a project, and unlinks it, at
  `/api/projects/:project_id/credentials/:id`.

  Linking needs an owner, admin or editor of the project, or the service
  account, and then the credential's owner or the service account. A
  credential isn't in the project until it is linked, so only the service
  account, which may read every credential, hears 404 `not_found` or 400
  `invalid_parameter` for its id; anyone else permitted on the project hears
  403 `forbidden`.

  Unlinking acts on the link, which is in the project, so anyone who may list
  the project's credentials hears 404 for a credential that isn't linked. It
  then needs the credential's owner, an owner or admin of the project, or the
  service account.
  """
  use LightningWeb, :controller

  alias Lightning.Credentials
  alias Lightning.Policies.Permissions
  alias Lightning.Scope
  alias LightningWeb.API.CredentialController
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction, {:credentials, :link_credential} when action == :update
  plug AuthorizeAction, {:credentials, :unlink_credential} when action == :delete

  @doc """
  Links the credential to the project and the project's sandboxes, answering
  201 with the credential, or 200 when it was already linked, changing
  nothing. The route takes no body, so any key sent is refused as
  `unknown_key`.

  An owner who isn't a member of the project is refused with a `no_access`
  entry at the path's `project_id`, and an `external_id` another credential
  linked to the project already has with a `taken` entry at the path's `id`.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, _params) do
    scope = conn.assigns.scope

    with {:ok, project} <-
           Target.project(
             scope,
             Request.param(conn, "project_id"),
             {:project_users, :create_project_credential}
           ),
         {:ok, credential} <-
           Target.record(
             scope,
             Request.param(conn, "id"),
             {:credentials, :link_credential},
             &CredentialController.fetch_credential/1
           ),
         :ok <- Request.check_object(conn.body_params),
         :ok <- Errors.refuse(Request.unknown_keys(conn.body_params, [], [])) do
      if Enum.any?(
           credential.project_credentials,
           &(&1.project_id == project.id)
         ),
         do: CredentialController.render_credential(conn, credential),
         else: link(conn, credential, project)
    end
  end

  defp link(conn, credential, project) do
    links =
      Enum.map(
        credential.project_credentials,
        &%{"id" => &1.id, "project_id" => &1.project_id}
      ) ++ [%{"project_id" => project.id}]

    with :ok <- Errors.refuse(owner_entries(credential, project)),
         {:ok, credential} <-
           write(credential, links, conn.assigns.current_resource) do
      conn
      |> put_status(:created)
      |> CredentialController.render_credential(credential)
    else
      # Another request linked it after the lookup. Rerun the request, which
      # now finds the link and answers as for a repeat.
      :link_taken -> update(conn, conn.params)
      error -> error
    end
  end

  defp owner_entries(credential, project) do
    case Credentials.projects_without_access(credential.user_id, [project.id]) do
      [] ->
        []

      _missing ->
        [
          Errors.entry(
            {:path, "project_id"},
            {"the credential's owner is not a member of this project",
             code: :no_access}
          )
        ]
    end
  end

  defp write(credential, links, actor) do
    case Credentials.update_credential(
           credential,
           %{"project_credentials" => links},
           actor
         ) do
      {:error, %Ecto.Changeset{} = changeset} ->
        if link_taken?(changeset),
          do: :link_taken,
          else:
            {:error, Errors.problem(changeset, %{external_id: :id}, path: [:id])}

      result ->
        result
    end
  end

  defp link_taken?(changeset) do
    changeset
    |> Ecto.Changeset.get_change(:project_credentials, [])
    |> Enum.any?(fn link ->
      link.errors
      |> Keyword.get_values(:project_id)
      |> Enum.any?(fn {_message, opts} -> opts[:constraint] == :unique end)
    end)
  end

  @doc """
  Unlinks the credential from the project, answering 204. Jobs in the project
  that use it lose it; links to the project's sandboxes stay. A credential
  that isn't linked to the project answers 404 `not_found`.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def delete(conn, _params) do
    scope = conn.assigns.scope

    with {:ok, link} <-
           Target.in_project(
             scope,
             Request.param(conn, "project_id"),
             {:project_users, :list_project_credentials},
             Request.param(conn, "id"),
             &Credentials.get_project_link/2
           ),
         {:ok, project_scope} <- Scope.fetch(scope, link),
         :ok <-
           Permissions.permit(
             :credentials,
             :unlink_credential,
             project_scope,
             link
           ),
         {:ok, _link} <-
           Credentials.unlink_credential(link, conn.assigns.current_resource) do
      send_resp(conn, :no_content, "")
    end
  end
end
