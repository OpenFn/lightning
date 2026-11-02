defmodule LightningWeb.API.WebhookAuthMethodController do
  @moduledoc """
  A project's webhook auth methods, for people: a personal access token or a
  session token. The service account and repo connections are refused 403
  `forbidden`.

      GET    /api/projects/:project_id/webhook_auth_methods
      GET    /api/projects/:project_id/webhook_auth_methods/:id
      PUT    /api/projects/:project_id/webhook_auth_methods/:id
      DELETE /api/projects/:project_id/webhook_auth_methods/:id

  Any member lists them, but only an owner or admin sees each one's `username`
  and `api_key_last_characters`, as only they reach the settings page's form.
  Reading, writing and deleting one is for an owner or admin. A method scheduled for deletion is left out of the list, and reading,
  replacing or deleting it again answers 409 `scheduled_for_deletion`.

  Secrets go out only in the `201` that creates an `api` method (its
  `api_key`) and to a stepped-up session token reading one.
  """
  use LightningWeb, :controller

  alias Lightning.Projects.Project
  alias Lightning.Scope
  alias Lightning.WebhookAuthMethods
  alias Lightning.Workflows.WebhookAuthMethod
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.API.WebhookAuthMethodJSON
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction,
       {:webhook_auth_methods, :list_webhook_auth_methods}
       when action == :index

  plug AuthorizeAction,
       {:webhook_auth_methods, :manage_webhook_auth_method}
       when action in [:show, :update, :delete]

  @list {:webhook_auth_methods, :list_webhook_auth_methods}
  @manage {:webhook_auth_methods, :manage_webhook_auth_method}

  @accepted [:id, :name, :auth_type, :username, :password]
  @attrs ~w(name auth_type username password)
  @unchangeable {"can't be changed", code: :not_allowed}

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, params) do
    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             @list
           ) do
      page =
        WebhookAuthMethods.paginate_for_project(project, Filters.page(params))

      hints? =
        match?(
          {:ok, _project},
          Target.project(conn.assigns.scope, project, @manage)
        )

      json(conn, WebhookAuthMethodJSON.index(conn, project, page, hints?))
    end
  end

  @doc """
  Reads a method. A stepped-up session token also gets its secret, `api_key`
  or `password`, as the settings page shows it again after reauthenticating.
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, _params) do
    with {:ok, auth_method} <- fetch(conn) do
      secrets = if Scope.stepped_up?(conn.assigns.scope), do: :secret, else: nil
      render_method(conn, auth_method, secrets)
    end
  end

  @doc """
  Creates the method under the path's id, or replaces the project's method
  that has it.

  A replace changes only `name`. `auth_type`, `username` and `password` may be
  sent again as they are, and are refused with a `not_allowed` entry when
  they differ, since Lightning can't change them. An id held by another
  project's method answers 409 `id_taken`.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, _params) do
    body = conn.body_params

    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             @manage
           ),
         {:ok, id} <- Request.id(Request.param(conn, "id")),
         {:ok, target} <- update_target(id, project),
         {:ok, entries} <- Request.check(body, id, @accepted) do
      case target do
        :new -> create(conn, project, id, body, entries)
        auth_method -> replace(conn, auth_method, body, entries)
      end
    end
  end

  @doc """
  Schedules the method for deletion, detaching it from its triggers and
  channels at once.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def delete(conn, _params) do
    with {:ok, auth_method} <- fetch(conn),
         {:ok, _scheduled} <-
           WebhookAuthMethods.schedule_for_deletion(auth_method,
             actor: conn.assigns.current_resource
           ) do
      send_resp(conn, :no_content, "")
    end
  end

  defp fetch(conn) do
    Target.in_project(
      conn.assigns.scope,
      Request.param(conn, "project_id"),
      @manage,
      Request.param(conn, "id"),
      &find_for_project/2
    )
  end

  defp find_for_project(project_id, id) do
    case WebhookAuthMethods.find_for_project(%Project{id: project_id}, id,
           include: [:triggers]
         ) do
      nil -> {:error, :not_found}
      auth_method -> live(auth_method)
    end
  end

  defp update_target(id, %Project{id: project_id}) do
    case WebhookAuthMethods.get(id) do
      nil -> {:ok, :new}
      %WebhookAuthMethod{project_id: ^project_id} = held -> live(held)
      %WebhookAuthMethod{} -> {:error, :id_taken}
    end
  end

  defp live(%WebhookAuthMethod{scheduled_deletion: nil} = auth_method),
    do: {:ok, auth_method}

  defp live(%WebhookAuthMethod{}), do: {:error, :scheduled_for_deletion}

  defp create(conn, project, id, body, entries) do
    attrs =
      body
      |> Map.take(@attrs)
      |> Map.put("project_id", project.id)

    changeset = WebhookAuthMethod.changeset(%WebhookAuthMethod{id: id}, attrs)

    with :ok <- Errors.refuse(entries ++ Errors.from_changeset(changeset)) do
      case WebhookAuthMethods.create_auth_method(attrs,
             actor: conn.assigns.current_resource,
             id: id
           ) do
        {:ok, auth_method} ->
          conn
          |> put_status(:created)
          |> render_method(%{auth_method | triggers: []}, :api_key)

        # Someone else created it since the lookup. Rerun the request so it
        # meets that method.
        {:error, %Ecto.Changeset{} = changeset} ->
          if Request.id_taken?(changeset),
            do: update(conn, conn.params),
            else: {:error, changeset}
      end
    end
  end

  defp replace(conn, auth_method, body, entries) do
    changeset =
      WebhookAuthMethod.update_changeset(auth_method, Map.take(body, ["name"]))

    with :ok <-
           Errors.refuse(
             entries ++
               unchangeable(auth_method, body) ++
               Errors.from_changeset(changeset)
           ),
         {:ok, auth_method} <- write(conn, auth_method, changeset) do
      render_method(conn, auth_method, nil)
    end
  end

  # A replace that changes nothing writes nothing, and no audit event.
  defp write(_conn, auth_method, %Ecto.Changeset{changes: changes})
       when map_size(changes) == 0,
       do: {:ok, auth_method}

  defp write(conn, auth_method, changeset) do
    WebhookAuthMethods.update_auth_method(auth_method, changeset.changes,
      actor: conn.assigns.current_resource
    )
  end

  defp unchangeable(auth_method, body) do
    for {key, stored} <- [
          {"auth_type", to_string(auth_method.auth_type)}
          | credentials(auth_method)
        ],
        Map.has_key?(body, key),
        not same?(body[key], stored),
        do: Errors.entry([key], @unchangeable)
  end

  # Compared with what a read shows: an api method's username and password
  # are null there, whatever the row holds.
  defp credentials(%WebhookAuthMethod{auth_type: :basic} = auth_method),
    do: [
      {"username", auth_method.username},
      {"password", auth_method.password}
    ]

  defp credentials(%WebhookAuthMethod{}),
    do: [{"username", nil}, {"password", nil}]

  defp same?(sent, stored) when is_binary(sent) and is_binary(stored),
    do: Plug.Crypto.secure_compare(sent, stored)

  defp same?(nil, nil), do: true
  defp same?(_sent, _stored), do: false

  defp render_method(conn, auth_method, secrets) do
    json(conn, WebhookAuthMethodJSON.show(conn, auth_method, secrets))
  end
end
