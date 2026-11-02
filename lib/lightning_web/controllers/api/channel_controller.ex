defmodule LightningWeb.API.ChannelController do
  @moduledoc """
  A project's channels, for people: a personal access token or a session
  token. The service account and repo connections are refused 403
  `forbidden`.

      GET    /api/projects/:project_id/channels
      GET    /api/projects/:project_id/channels/:id
      PUT    /api/projects/:project_id/channels/:id
      DELETE /api/projects/:project_id/channels/:id

  Any member reads them; owners, admins and editors write and delete them.

  `client_auth_method_ids` are the project's webhook auth methods, and
  `destination_credential_id` is a credential linked to the project, which
  Lightning stores as the project credential that links them.
  """
  use LightningWeb, :controller

  alias Lightning.Channels
  alias Lightning.Channels.Channel
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.WebhookAuthMethods
  alias LightningWeb.API.ChannelJSON
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction,
       {:channels, :access_channels} when action in [:index, :show]

  plug AuthorizeAction, {:channels, :write_channel} when action == :update
  plug AuthorizeAction, {:channels, :delete_channel} when action == :delete

  @access {:channels, :access_channels}
  @write {:channels, :write_channel}
  @delete {:channels, :delete_channel}

  @accepted [
    :id,
    :name,
    :destination_url,
    :enabled,
    :client_auth_method_ids,
    :destination_credential_id,
    :lock_version
  ]

  @auth_methods [
    :client_auth_methods,
    destination_auth_method: :project_credential
  ]

  @not_a_uuid {"is not a UUID", code: :type}
  @invalid {"is invalid", code: :type}

  @doc """
  Lists the project's channels by name, a page at a time. `meta` carries the
  whole project's `total_channels` and `total_requests`, whatever the page.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, params) do
    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             @access
           ) do
      page =
        Channels.paginate_channels_for_project_with_stats(
          project.id,
          Filters.page(params)
        )

      totals = Channels.get_channel_stats_for_project(project.id)

      json(conn, ChannelJSON.index(conn, page, totals))
    end
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, _params) do
    with {:ok, entry} <-
           Target.in_project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             @access,
             Request.param(conn, "id"),
             &get_with_stats/2
           ) do
      json(conn, ChannelJSON.show(entry))
    end
  end

  @doc """
  Creates the channel under the path's id, or replaces the project's channel
  that has it.

  A replace that leaves out `enabled`, `client_auth_method_ids` or
  `destination_credential_id` keeps what the channel has, so a rename never
  opens a channel by dropping its auth methods. `lock_version`, when sent,
  refuses the write with 409 `concurrent_edit` if the channel has changed
  since. An id held by another project's channel answers 409 `id_taken`.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, _params) do
    body = conn.body_params

    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             @write
           ),
         {:ok, id} <- Request.id(Request.param(conn, "id")),
         {:ok, target} <- update_target(id, project),
         {:ok, entries} <- Request.check(body, id, @accepted) do
      {references, entries} = references(project, body, entries)
      attrs = attrs(project, target, body, references)

      changeset =
        case target do
          :new -> Channel.changeset(%Channel{id: id}, attrs)
          channel -> Channel.changeset(channel, attrs)
        end

      with :ok <-
             Errors.refuse(entries ++ Errors.from_changeset(changeset)) do
        case target do
          :new -> create(conn, project, id, attrs)
          channel -> replace(conn, project, channel, attrs, body)
        end
      end
    end
  end

  @doc """
  Deletes the channel and every request recorded for it. A request arriving
  while it deletes answers 409 `concurrent_edit`, and the delete can be sent
  again.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def delete(conn, _params) do
    with {:ok, channel} <-
           Target.in_project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             @delete,
             Request.param(conn, "id"),
             &get_channel/2
           ),
         {:ok, _deleted} <-
           Channels.delete_channel(channel,
             actor: conn.assigns.current_resource
           ) do
      send_resp(conn, :no_content, "")
    end
  end

  defp get_with_stats(project_id, id) do
    case Channels.get_channel_with_stats_for_project(project_id, id) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  defp get_channel(project_id, id) do
    case Channels.get_channel_for_project(project_id, id) do
      nil -> {:error, :not_found}
      channel -> {:ok, channel}
    end
  end

  defp update_target(id, %Project{id: project_id}) do
    case Channels.get_channel(id, include: @auth_methods) do
      nil -> {:ok, :new}
      %Channel{project_id: ^project_id} = channel -> {:ok, channel}
      %Channel{} -> {:error, :id_taken}
    end
  end

  defp create(conn, project, id, attrs) do
    case Channels.create_channel(attrs,
           actor: conn.assigns.current_resource,
           id: id
         ) do
      {:ok, _channel} ->
        with {:ok, entry} <- get_with_stats(project.id, id) do
          conn |> put_status(:created) |> json(ChannelJSON.show(entry))
        end

      # Someone else created it since the lookup. Rerun the request so it
      # meets that channel.
      {:error, %Ecto.Changeset{} = changeset} ->
        if Request.id_taken?(changeset),
          do: update(conn, conn.params),
          else: {:error, changeset}
    end
  end

  defp replace(conn, project, channel, attrs, body) do
    with {:ok, channel} <- at_version(channel, body["lock_version"]),
         {:ok, _channel} <-
           Channels.update_channel(channel, attrs,
             actor: conn.assigns.current_resource
           ),
         {:ok, entry} <- get_with_stats(project.id, channel.id) do
      json(conn, ChannelJSON.show(entry))
    end
  end

  # The write checks the version on the struct, so the caller's goes there. A
  # replace that changes nothing doesn't write, so it is checked here too.
  defp at_version(channel, nil), do: {:ok, channel}

  defp at_version(%Channel{lock_version: version} = channel, version),
    do: {:ok, channel}

  defp at_version(_channel, _version), do: {:error, :concurrent_edit}

  defp attrs(project, target, body, references) do
    current = if target == :new, do: nil, else: target

    body
    |> Map.take(["name", "destination_url", "enabled"])
    |> Map.put("project_id", project.id)
    |> Map.put("client_auth_methods", client_rows(current, references))
    |> put_destination(current, references)
  end

  # The project's webhook auth methods and project credential the body names,
  # checked against the project, and an entry for each one that isn't there.
  defp references(project, body, entries) do
    {clients, client_entries} = client_references(project, body)
    {destination, destination_entries} = destination_reference(project, body)

    {%{clients: clients, destination: destination},
     entries ++ client_entries ++ destination_entries ++ version_entries(body)}
  end

  defp version_entries(%{"lock_version" => version})
       when not is_integer(version) and not is_nil(version),
       do: [Errors.entry(["lock_version"], @invalid)]

  defp version_entries(_body), do: []

  defp client_references(_project, body)
       when not is_map_key(body, "client_auth_method_ids"),
       do: {:keep, []}

  defp client_references(project, %{"client_auth_method_ids" => ids})
       when is_list(ids) do
    usable =
      project |> WebhookAuthMethods.list_for_project() |> MapSet.new(& &1.id)

    entries =
      for {id, index} <- Enum.with_index(ids),
          entry = client_entry(id, index, usable),
          do: entry

    {ids |> Enum.filter(&MapSet.member?(usable, &1)) |> Enum.uniq(), entries}
  end

  defp client_references(_project, _body),
    do: {:keep, [Errors.entry(["client_auth_method_ids"], @invalid)]}

  defp client_entry(id, index, usable) do
    location = ["client_auth_method_ids", index]

    cond do
      match?({:error, _}, Request.id({location, id})) ->
        Errors.entry(location, @not_a_uuid)

      not MapSet.member?(usable, id) ->
        Errors.entry(location, Errors.not_visible())

      true ->
        nil
    end
  end

  defp destination_reference(_project, body)
       when not is_map_key(body, "destination_credential_id"),
       do: {:keep, []}

  defp destination_reference(_project, %{"destination_credential_id" => nil}),
    do: {nil, []}

  defp destination_reference(project, %{"destination_credential_id" => id}) do
    location = ["destination_credential_id"]

    with {:ok, id} <- Request.id({location, id}),
         %{} = project_credential <-
           Projects.get_project_credential(project.id, id) do
      {project_credential.id, []}
    else
      {:error, _invalid} -> {:keep, [Errors.entry(location, @not_a_uuid)]}
      nil -> {:keep, [Errors.entry(location, Errors.not_visible())]}
    end
  end

  # The full set of client rows the channel should end with: the rows it
  # keeps by id, a new row for each method it gains, and a delete for each
  # row it loses.
  defp client_rows(nil, %{clients: :keep}), do: []

  defp client_rows(nil, %{clients: ids}),
    do: Enum.map(ids, &%{"webhook_auth_method_id" => &1})

  defp client_rows(channel, %{clients: :keep}),
    do: Enum.map(channel.client_auth_methods, &%{"id" => &1.id})

  defp client_rows(channel, %{clients: ids}) do
    existing = channel.client_auth_methods

    kept_or_dropped =
      Enum.map(existing, fn row ->
        if row.webhook_auth_method_id in ids,
          do: %{"id" => row.id},
          else: %{"id" => row.id, "delete" => true}
      end)

    held = Enum.map(existing, & &1.webhook_auth_method_id)

    kept_or_dropped ++
      for id <- ids, id not in held, do: %{"webhook_auth_method_id" => id}
  end

  defp put_destination(attrs, _current, %{destination: :keep}), do: attrs

  defp put_destination(attrs, current, %{destination: project_credential_id}) do
    existing = current && current.destination_auth_method

    case {existing, project_credential_id} do
      {nil, nil} ->
        attrs

      {%{}, nil} ->
        Map.put(attrs, "destination_auth_method", nil)

      {%{id: id, project_credential_id: ^project_credential_id}, _} ->
        Map.put(attrs, "destination_auth_method", %{"id" => id})

      {_existing, _new} ->
        Map.put(attrs, "destination_auth_method", %{
          "project_credential_id" => project_credential_id
        })
    end
  end
end
