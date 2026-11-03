defmodule LightningWeb.API.OauthClientController do
  @moduledoc """
  OAuth clients: the app registrations `oauth` credentials get their tokens
  through. `client_secret` is never rendered.

      GET /api/oauth_clients
      GET /api/projects/:project_id/oauth_clients
      PUT /api/oauth_clients/:id
      DELETE /api/oauth_clients/:id

  The lists are paged. Without a project, a person lists their own clients and
  the global ones; the service account owns none, so it must name a project.
  With a project, the clients linked to it and the global ones.

  A client belongs to the person who created it. Only they may replace or
  delete it, and the service account, which can't own one, may do neither.
  """
  use LightningWeb, :controller

  alias Lightning.Credentials.OauthClient
  alias Lightning.OauthClients
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Scope
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction,
       {:credentials, :list_credentials}
       when action == :index

  plug AuthorizeAction,
       {:project_users, :list_project_credentials}
       when action == :index_for_project

  plug AuthorizeAction,
       {:credentials, :create_oauth_client}
       when action == :update

  plug AuthorizeAction,
       {:credentials, :delete_oauth_client}
       when action == :delete

  @fields [
    :name,
    :client_id,
    :authorization_endpoint,
    :token_endpoint,
    :revocation_endpoint,
    :userinfo_endpoint,
    :introspection_endpoint,
    :scopes_doc_url,
    :mandatory_scopes,
    :optional_scopes
  ]

  @accepted [:id, :client_secret, :global, :project_ids | @fields]

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, params) do
    scope = conn.assigns.scope

    with :ok <- Permissions.permit(:credentials, :list_credentials, scope, nil) do
      list(conn, scope.actor, params)
    end
  end

  @spec index_for_project(Plug.Conn.t(), map()) ::
          Plug.Conn.t() | {:error, term()}
  def index_for_project(conn, params) do
    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             {:project_users, :list_project_credentials}
           ) do
      list(conn, project, params)
    end
  end

  @doc """
  Creates the client under the path's id, owned by the caller, or replaces the
  one that has it, which only its owner may. A replace sets every field the
  body leaves out to empty, except `client_secret`, which it keeps, and
  `global`. `project_ids` is the client's whole list of links among the
  projects the caller can see. A link to a project they can't see, which the
  client's JSON leaves out, is kept whatever the body says.

  Only a superuser may change `global`, and linking a project needs editor or
  above in it. A refused body answers one 422 with every error together.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, _params) do
    scope = conn.assigns.scope
    body = conn.body_params

    with :ok <-
           Permissions.permit(:credentials, :create_oauth_client, scope, nil),
         {:ok, id} <- Request.id(Request.param(conn, "id")),
         {:ok, target} <- update_target(id, scope),
         {:ok, key_entries} <- Request.check(body, id, @accepted) do
      current = if target == :new, do: %OauthClient{}, else: target
      {link_entries, links} = links(body, current, scope)
      attrs = attrs(body, current, links)

      entries =
        key_entries ++
          global_entries(body, current, scope) ++
          link_entries ++
          Errors.from_changeset(changeset(current, attrs, scope))

      with :ok <- Errors.refuse(entries) do
        case target do
          :new -> create(conn, id, attrs)
          client -> replace(conn, client, attrs)
        end
      end
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def delete(conn, _params) do
    with {:ok, client} <-
           Target.record(
             conn.assigns.scope,
             Request.param(conn, "id"),
             {:credentials, :delete_oauth_client},
             &fetch_client/1
           ),
         {:ok, _deleted} <-
           OauthClients.delete_client(client, conn.assigns.current_resource) do
      send_resp(conn, :no_content, "")
    end
  end

  defp list(conn, project_or_user, params) do
    page =
      project_or_user
      |> OauthClients.paginate_clients(Filters.page(params))
      |> Map.update!(:entries, &hide_unseen_links(&1, conn.assigns.scope))

    render(conn, :index, page: page, filters: %{})
  end

  defp update_target(id, scope) do
    case OauthClients.get_client(id) do
      nil ->
        {:ok, :new}

      client ->
        with :ok <-
               Permissions.permit(
                 :credentials,
                 :edit_oauth_client,
                 scope,
                 client
               ),
             do: {:ok, client}
    end
  end

  defp fetch_client(id) do
    case OauthClients.get_client(id) do
      nil -> {:error, :not_found}
      client -> {:ok, client}
    end
  end

  # Every field the body leaves out is emptied, except the secret, which is
  # kept, and `global`, which keeps its value.
  defp attrs(body, current, links) do
    @fields
    |> Map.new(&{Atom.to_string(&1), body[Atom.to_string(&1)]})
    |> Map.put("global", Map.get(body, "global", current.global))
    |> Map.put("project_oauth_clients", links)
    |> then(fn attrs ->
      case body do
        %{"client_secret" => secret} -> Map.put(attrs, "client_secret", secret)
        _keeps_it -> attrs
      end
    end)
  end

  defp changeset(%OauthClient{id: nil} = client, attrs, scope),
    do: OauthClient.create_changeset(client, attrs, global_opts(scope))

  defp changeset(client, attrs, scope),
    do: OauthClient.changeset(client, attrs, global_opts(scope))

  defp global_opts(scope),
    do: [allow_global: scope.instance_role == :superuser]

  # Only a superuser may change whether a client is global. Sending the value
  # it already has changes nothing, so anyone may.
  defp global_entries(%{"global" => global}, current, scope) do
    if global == current.global or scope.instance_role == :superuser,
      do: [],
      else: [
        Errors.entry(
          [:global],
          {"can only be changed by a superuser", code: :not_allowed}
        )
      ]
  end

  defp global_entries(_body, _current, _scope), do: []

  # The links the client keeps, each with its id so `cast_assoc` keeps it, the
  # ones it loses, marked for deletion, and the new ones, each refused unless
  # the caller may link a credential in that project. A held link to a project
  # the caller can't see was never shown to them, so it is kept.
  defp links(%{"project_ids" => ids}, current, scope) when is_list(ids) do
    held = held_links(current)
    shown = shown_project_ids(scope, Map.keys(held))

    checked =
      ids
      |> Enum.with_index()
      |> Enum.map(fn {id, index} -> {index, link_id(id, index)} end)

    new_ids =
      for {_index, {:ok, id}} <- checked, not Map.has_key?(held, id), do: id

    scopes = Scope.fetch_all(scope, new_ids)

    results =
      Enum.map(checked, fn
        {_index, {:ok, id}} when is_map_key(held, id) ->
          {:ok, id}

        {index, {:ok, id}} ->
          case link_refusal(scopes[id]) do
            nil -> {:ok, id}
            refusal -> {:error, Errors.entry([:project_ids, index], refusal)}
          end

        {_index, error} ->
          error
      end)

    wanted = Enum.uniq(for {:ok, id} <- results, do: id)

    links =
      Enum.map(held, fn {project_id, link_id} ->
        if project_id in wanted or project_id not in shown,
          do: %{"id" => link_id, "project_id" => project_id},
          else: %{"id" => link_id, "delete" => "true"}
      end) ++
        for id <- wanted, not Map.has_key?(held, id), do: %{"project_id" => id}

    {for({:error, entry} <- results, do: entry), links}
  end

  defp links(%{"project_ids" => _ids}, current, _scope),
    do:
      {[Errors.entry([:project_ids], {"is invalid", code: :type})],
       keep_links(current)}

  defp links(_body, current, _scope), do: {[], keep_links(current)}

  defp held_links(%OauthClient{id: nil}), do: %{}

  defp held_links(%OauthClient{project_oauth_clients: links}),
    do: Map.new(links, &{&1.project_id, &1.id})

  defp keep_links(current) do
    current
    |> held_links()
    |> Enum.map(fn {project_id, id} ->
      %{"id" => id, "project_id" => project_id}
    end)
  end

  defp link_id(id, index) when is_binary(id) do
    case Request.id({[:project_ids, index], id}) do
      {:ok, id} ->
        {:ok, id}

      {:error, _invalid} ->
        {:error, Errors.entry([:project_ids, index], Errors.not_visible())}
    end
  end

  defp link_id(_id, index),
    do:
      {:error, Errors.entry([:project_ids, index], {"is invalid", code: :type})}

  # A project the caller can't see is named as missing, the same as one that
  # doesn't exist. One they can see but may not link to is `no_access`.
  defp link_refusal(nil), do: Errors.not_visible()

  defp link_refusal(project_scope) do
    case ProjectUsers.authorize(
           :create_project_credential,
           project_scope,
           project_scope.project
         ) do
      true ->
        nil

      {:error, :no_standing} ->
        Errors.not_visible()

      _refused ->
        {"you may not link an OAuth client to this project", code: :no_access}
    end
  end

  defp create(conn, id, attrs) do
    actor = conn.assigns.current_resource

    attrs
    |> Map.put("user_id", actor.id)
    |> OauthClients.create_client(actor,
      id: id,
      allow_global: conn.assigns.scope.instance_role == :superuser
    )
    |> case do
      {:ok, client} ->
        conn |> put_status(:created) |> render_client(client)

      # Someone else created it since the lookup. Rerun the request so the
      # caller is checked against that client.
      {:error, %Ecto.Changeset{} = changeset} ->
        if Request.id_taken?(changeset),
          do: update(conn, conn.params),
          else: {:error, changeset}

      error ->
        error
    end
  end

  defp replace(conn, client, attrs) do
    with {:ok, client} <-
           OauthClients.update_client(
             client,
             attrs,
             conn.assigns.current_resource,
             allow_global: conn.assigns.scope.instance_role == :superuser
           ) do
      render_client(conn, client)
    end
  end

  defp render_client(conn, client) do
    case fetch_client(client.id) do
      {:ok, client} ->
        [client] = hide_unseen_links([client], conn.assigns.scope)
        render(conn, :show, oauth_client: client)

      {:error, :not_found} ->
        {:error, :concurrent_edit}
    end
  end

  # A client can be linked to projects the caller has no standing in, such as
  # a global client someone else linked to their own projects. Those links are
  # left out.
  defp hide_unseen_links(clients, scope) do
    shown =
      shown_project_ids(
        scope,
        clients
        |> Enum.flat_map(& &1.project_oauth_clients)
        |> Enum.map(& &1.project_id)
        |> Enum.uniq()
      )

    Enum.map(clients, fn client ->
      %{
        client
        | project_oauth_clients:
            Enum.filter(client.project_oauth_clients, &(&1.project_id in shown))
      }
    end)
  end

  # The projects among `project_ids` whose links the caller is shown: those
  # whose credentials they may list.
  defp shown_project_ids(scope, project_ids) do
    for {id, project_scope} <- Scope.fetch_all(scope, project_ids),
        ProjectUsers.permitted?(:list_project_credentials, project_scope),
        into: MapSet.new(),
        do: id
  end
end
