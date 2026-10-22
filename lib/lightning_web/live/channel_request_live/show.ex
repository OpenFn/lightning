defmodule LightningWeb.ChannelRequestLive.Show do
  @moduledoc """
  One request through a channel: what it sent, what came back, how long it
  took and the config it ran on. The page has no events; the LiveView's job
  is the gates and the props.
  """
  use LightningWeb, :live_view

  alias Lightning.Channels
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects
  alias LightningWeb.ChannelRequestLive.Helpers

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    %{current_user: current_user, project: project, project_user: project_user} =
      socket.assigns

    if Lightning.Accounts.experimental_features_enabled?(current_user) do
      case Channels.get_channel_request_for_project(project.id, id) do
        nil ->
          {:ok, redirect(socket, to: ~p"/projects/#{project}/history")}

        channel_request ->
          can_edit_data_retention =
            Permissions.can?(
              ProjectUsers,
              :edit_data_retention,
              current_user,
              project_user
            )

          {:ok,
           assign(socket,
             active_menu_item: :runs,
             page_title: "Channel Request",
             channel_request: channel_request,
             can_edit_data_retention: can_edit_data_retention,
             # The emails are shown only to someone who cannot change the
             # policy, on a wiped request; nobody else gets them.
             admin_contacts:
               if(channel_request.is_wiped and not can_edit_data_retention,
                 do: Projects.list_project_admin_emails(project.id),
                 else: []
               )
           )}
      end
    else
      {:ok, redirect(socket, to: ~p"/projects/#{project}/history")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.design_system_page
      name="ChannelRequestShowPage"
      props={
        %{
          project: %{
            id: @project.id,
            parentId: @project.parent_id,
            color: @project.color
          },
          projectLabel: @project_label,
          request: request_json(@channel_request),
          channel: channel_json(@channel_request.channel),
          canEditDataRetention: @can_edit_data_retention,
          adminContacts: @admin_contacts
        }
      }
      current_user={@current_user}
    />
    """
  end

  # The shape the design system's ChannelRequestDetail type expects: what
  # the old page rendered, and only the event it rendered.
  defp request_json(cr) do
    snapshot = cr.channel_snapshot

    %{
      id: cr.id,
      state: cr.state,
      startedAt: cr.started_at,
      completedAt: cr.completed_at,
      clientIdentity: cr.client_identity,
      clientAuth: Helpers.format_client_auth(cr),
      destinationAuth: Helpers.format_destination_auth(cr),
      isWiped: cr.is_wiped,
      snapshot: %{
        name: snapshot.name,
        destinationUrl: snapshot.destination_url,
        lockVersion: snapshot.lock_version
      },
      events:
        case Helpers.primary_event(cr) do
          nil -> []
          event -> [event_json(event)]
        end
    }
  end

  defp event_json(event) do
    %{
      type: event.type,
      requestMethod: event.request_method,
      requestPath: event.request_path,
      requestQueryString: event.request_query_string,
      requestHeaders: event.request_headers,
      requestBodyPreview: event.request_body_preview,
      requestBodySize: event.request_body_size,
      requestBodyHash: event.request_body_hash,
      responseStatus: event.response_status,
      responseHeaders: event.response_headers,
      responseBodyPreview: event.response_body_preview,
      responseBodySize: event.response_body_size,
      responseBodyHash: event.response_body_hash,
      latencyUs: event.latency_us,
      ttfbUs: event.ttfb_us,
      queueUs: event.queue_us,
      connectUs: event.connect_us,
      requestSendUs: event.request_send_us,
      responseDurationUs: event.response_duration_us,
      reusedConnection: event.reused_connection == true,
      errorMessage: event.error_message
    }
  end

  # The channel as it is now; the Context section shows the snapshot.
  defp channel_json(channel) do
    %{
      id: channel.id,
      projectId: channel.project_id,
      name: channel.name,
      destinationUrl: channel.destination_url,
      lockVersion: channel.lock_version
    }
  end
end
