defmodule LightningWeb.ChannelLive.Index do
  @moduledoc false
  use LightningWeb, :live_view

  import LightningWeb.ChannelLive.Helpers

  alias Lightning.Channels
  alias Lightning.Channels.Channel
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects
  alias Lightning.WebhookAuthMethods

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :check_limits}

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: current_user, project: project} = socket.assigns

    can_create_channel =
      ProjectUsers
      |> Permissions.can?(:create_channel, current_user, project)

    can_edit_channel =
      ProjectUsers
      |> Permissions.can?(:update_channel, current_user, project)

    can_delete_channel =
      ProjectUsers
      |> Permissions.can?(:delete_channel, current_user, project)

    {:ok,
     socket
     |> assign(
       active_menu_item: :channels,
       can_create_channel: can_create_channel,
       can_edit_channel: can_edit_channel,
       can_delete_channel: can_delete_channel,
       channels: [],
       channel_stats: %{total_channels: 0, total_requests: 0}
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    project_id = socket.assigns.project.id

    socket
    |> assign(
      page_title: "Channels",
      channels: Channels.list_channels_for_project_with_stats(project_id),
      channel_stats: Channels.get_channel_stats_for_project(project_id),
      selected_channel: nil
    )
  end

  defp apply_action(socket, :new, _params) do
    if socket.assigns.can_create_channel do
      socket
      |> assign(
        page_title: "New Channel",
        selected_channel: %Channel{
          channel_auth_methods: [],
          client_auth_methods: [],
          destination_auth_method: nil
        }
      )
      |> assign_form_options()
    else
      socket
      |> put_flash(:error, "You are not authorized to create channels.")
      |> push_navigate(to: ~p"/projects/#{socket.assigns.project.id}/channels")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    if socket.assigns.can_edit_channel do
      channel =
        Channels.get_channel_for_project(socket.assigns.project.id, id,
          include: [
            :client_auth_methods,
            :destination_auth_method
          ]
        )

      if channel do
        socket
        |> assign(
          page_title: "Edit Channel",
          selected_channel: channel
        )
        |> assign_form_options()
      else
        socket
        |> put_flash(:error, "Channel not found")
        |> push_navigate(to: ~p"/projects/#{socket.assigns.project.id}/channels")
      end
    else
      socket
      |> put_flash(:error, "You are not authorized to edit channels.")
      |> push_navigate(to: ~p"/projects/#{socket.assigns.project.id}/channels")
    end
  end

  # The form's options, as the form component loaded them when it opened.
  defp assign_form_options(socket) do
    project = socket.assigns.project

    assign(socket,
      webhook_auth_methods: WebhookAuthMethods.list_for_project(project),
      project_credentials: Projects.list_project_credentials(project)
    )
  end

  @impl true
  def handle_event(
        "toggle_channel_state",
        %{"channel_state" => enabled?, "value_key" => channel_id},
        socket
      ) do
    with :ok <- authorize_action(socket, :edit_channel),
         {:ok, channel} <- fetch_project_channel(socket, channel_id) do
      case Channels.update_channel(channel, %{enabled: enabled?},
             actor: socket.assigns.current_user
           ) do
        {:ok, _channel} ->
          socket
          |> put_flash(:info, "Channel updated")
          |> push_patch(to: ~p"/projects/#{socket.assigns.project.id}/channels")
          |> reply_ok()

        {:error, _changeset} ->
          socket
          |> put_flash(:error, "Failed to update channel. Please try again.")
          |> reply_ok()
      end
    end
  end

  def handle_event("delete_channel", %{"id" => id}, socket) do
    with :ok <- authorize_action(socket, :delete_channel),
         {:ok, channel} <- fetch_project_channel(socket, id) do
      case Channels.delete_channel(channel, actor: socket.assigns.current_user) do
        {:ok, _} ->
          socket
          |> put_flash(:info, "Channel deleted.")
          |> push_patch(to: ~p"/projects/#{socket.assigns.project.id}/channels")
          |> reply_ok()

        {:error, changeset} ->
          message =
            if Keyword.has_key?(changeset.errors, :channel_snapshots),
              do:
                "Cannot delete \"#{channel.name}\" — it has request history that must be retained.",
              else: "Failed to delete channel. Please try again."

          socket |> put_flash(:error, message) |> reply_ok()
      end
    end
  end

  # The open form's Save. Which form is open, and whether this user may save
  # it, is the route's and the server's to know, not the payload's.
  def handle_event("save_channel", params, socket) do
    %{
      live_action: action,
      can_create_channel: can_create?,
      can_edit_channel: can_edit?
    } = socket.assigns

    channel = socket.assigns[:selected_channel]

    cond do
      action == :new and can_create? and match?(%Channel{id: nil}, channel) ->
        create_channel(socket, params)

      action == :edit and can_edit? and
          match?(%Channel{id: id} when is_binary(id), channel) ->
        update_channel(socket, channel, params)

      true ->
        reply_error(socket, "You are not authorized to perform this action.")
    end
  end

  defp create_channel(socket, params) do
    attrs =
      params
      |> channel_attrs([], nil)
      |> Map.put("project_id", socket.assigns.project.id)

    case Channels.create_channel(attrs, actor: socket.assigns.current_user) do
      {:ok, _channel} ->
        socket
        |> put_flash(:info, "Channel created successfully.")
        |> push_patch(to: ~p"/projects/#{socket.assigns.project}/channels")
        |> reply_ok()

      {:error, changeset} ->
        reply_error(socket, changeset)
    end
  end

  defp update_channel(socket, channel, params) do
    attrs =
      channel_attrs(
        params,
        channel.client_auth_methods,
        channel.destination_auth_method
      )

    case Channels.update_channel(channel, attrs,
           actor: socket.assigns.current_user
         ) do
      {:ok, _channel} ->
        socket
        |> put_flash(:info, "Channel updated successfully.")
        |> push_patch(to: ~p"/projects/#{socket.assigns.project}/channels")
        |> reply_ok()

      {:error, changeset} ->
        reply_error(socket, changeset)
    end
  end

  # The page's camelCase values as the changeset's params, with the auth
  # methods as the nested changes the schema expects: existing clients kept
  # or deleted, new ones added, and the destination kept, swapped or cleared.
  defp channel_attrs(params, current_clients, current_destination) do
    attrs = %{
      "name" => params["name"],
      "destination_url" => params["destinationUrl"],
      "client_auth_methods" =>
        build_client_auth_params(params["clientAuthMethodIds"], current_clients)
    }

    # The page always sends it; a payload without it leaves the switch alone.
    attrs =
      if Map.has_key?(params, "enabled"),
        do: Map.put(attrs, "enabled", params["enabled"]),
        else: attrs

    case build_destination_auth_param(
           params["destinationCredentialId"],
           current_destination
         ) do
      nil -> attrs
      :clear -> Map.put(attrs, "destination_auth_method", nil)
      dest -> Map.put(attrs, "destination_auth_method", dest)
    end
  end

  defp build_client_auth_params(ids, current_clients) do
    ids = if is_list(ids), do: Enum.filter(ids, &is_binary/1), else: []
    current_ids = Enum.map(current_clients, & &1.webhook_auth_method_id)

    kept_or_dropped =
      Enum.map(current_clients, fn cam ->
        if cam.webhook_auth_method_id in ids,
          do: %{id: cam.id},
          else: %{id: cam.id, delete: true}
      end)

    added =
      ids
      |> Enum.uniq()
      |> Enum.reject(&(&1 in current_ids))
      |> Enum.map(&%{webhook_auth_method_id: &1})

    kept_or_dropped ++ added
  end

  defp build_destination_auth_param(selected_id, current_destination) do
    selected_id = if selected_id in [nil, ""], do: nil, else: selected_id

    case {current_destination, selected_id} do
      {nil, nil} -> nil
      {%{}, nil} -> :clear
      {%{id: id, project_credential_id: pc_id}, pc_id} -> %{id: id}
      {_, _} -> %{project_credential_id: selected_id}
    end
  end

  @action_assigns %{
    edit_channel: :can_edit_channel,
    delete_channel: :can_delete_channel
  }

  defp authorize_action(socket, action)
       when action in [:edit_channel, :delete_channel] do
    if socket.assigns[@action_assigns[action]] do
      :ok
    else
      socket
      |> put_flash(:error, "You are not authorized to perform this action.")
      |> reply_ok()
    end
  end

  defp fetch_project_channel(socket, channel_id) do
    case Channels.get_channel_for_project(socket.assigns.project.id, channel_id) do
      %{} = channel -> {:ok, channel}
      nil -> socket |> put_flash(:error, "Channel not found") |> reply_ok()
    end
  end

  # The kit's send resolves on this; the flash says what happened.
  defp reply_ok(socket), do: {:reply, %{}, socket}

  # --- Props ---

  # The shape the design system's ChannelRow type expects.
  defp channels_json(channels, project) do
    Enum.map(channels, fn %{
                            channel: channel,
                            request_count: count,
                            last_activity: last_at
                          } ->
      %{
        id: channel.id,
        name: channel.name,
        enabled: channel.enabled,
        destinationUrl: channel.destination_url,
        proxyUrl: channel_proxy_url(channel.id),
        requestCount: count,
        lastActivityAt: last_at,
        logsHref:
          ~p"/projects/#{project}/history/channels?#{%{filters: %{channel_id: channel.id}}}"
      }
    end)
  end

  # The design system's ChannelForm while the route has the form open.
  defp form_json(action, channel, project_credentials, webhook_auth_methods)
       when action in [:new, :edit] and is_list(project_credentials) do
    %{
      channel: channel_form_json(action, channel),
      credentialOptions:
        Enum.map(project_credentials, &%{id: &1.id, name: &1.credential.name}),
      authMethodOptions:
        Enum.map(webhook_auth_methods, &%{id: &1.id, name: &1.name})
    }
  end

  defp form_json(_action, _channel, _credentials, _methods), do: nil

  defp channel_form_json(:new, _channel), do: nil

  defp channel_form_json(:edit, channel) do
    %{
      id: channel.id,
      proxyUrl: channel_proxy_url(channel.id),
      name: channel.name,
      enabled: channel.enabled,
      destinationUrl: channel.destination_url,
      destinationCredentialId:
        (channel.destination_auth_method &&
           channel.destination_auth_method.project_credential_id) || "",
      clientAuthMethodIds:
        Enum.map(channel.client_auth_methods, & &1.webhook_auth_method_id)
    }
  end
end
