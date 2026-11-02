defmodule LightningWeb.API.ChannelRequestJSON do
  @moduledoc """
  Renders the requests a project's channels recorded. A request's `path`,
  `error_message`, request, response and timing come from its primary event,
  the destination's response or else the error, as the request page reads
  them. Headers are stored redacted and bodies stored as previews, so they go
  out as they are.
  """
  import LightningWeb.API.Helpers

  alias LightningWeb.ChannelRequestLive.Helpers

  def index(conn, page, filters) do
    %{
      data: Enum.map(page.entries, &resource(&1, %{})),
      links: pagination_links(conn, page, filters)
    }
  end

  def show(request) do
    event = Helpers.primary_event(request)

    %{
      data:
        resource(request, %{
          client_identity: request.client_identity,
          client_auth: client_auth(request),
          destination_credential: destination_credential(request),
          channel_snapshot: snapshot(request.channel_snapshot),
          request: request_part(event),
          response: response_part(event),
          error_category: error_category(event),
          timing: timing(event),
          wiped: request.is_wiped
        })
    }
  end

  defp resource(request, details) do
    event = Helpers.primary_event(request)

    %{
      type: "channel_requests",
      id: request.id,
      attributes:
        Map.merge(
          %{
            channel_id: request.channel_id,
            request_id: request.request_id,
            state: request.state,
            path: event && event.request_path,
            error_message: event && event.error_message,
            started_at: request.started_at,
            completed_at: request.completed_at
          },
          details
        ),
      relationships: %{},
      links: %{
        self: "#{LightningWeb.Endpoint.url()}/api/channel_requests/#{request.id}"
      }
    }
  end

  defp client_auth(request) do
    %{
      type: request.client_auth_type,
      method_id: request.client_webhook_auth_method_id,
      method_name:
        request.client_webhook_auth_method &&
          request.client_webhook_auth_method.name
    }
  end

  defp destination_credential(%{destination_credential_id: nil}), do: nil

  defp destination_credential(request) do
    %{
      id: request.destination_credential_id,
      name:
        case request.destination_credential do
          %{credential: %{name: name}} -> name
          _deleted -> nil
        end
    }
  end

  defp snapshot(nil), do: nil

  defp snapshot(snapshot) do
    Map.take(snapshot, [:name, :destination_url, :lock_version])
  end

  defp request_part(nil), do: nil

  defp request_part(event) do
    %{
      method: event.request_method,
      path: event.request_path,
      query_string: event.request_query_string,
      headers: event.request_headers,
      body: event.request_body_preview,
      body_size: event.request_body_size
    }
  end

  defp response_part(nil), do: nil

  defp response_part(event) do
    %{
      status: event.response_status,
      headers: event.response_headers,
      body: event.response_body_preview,
      body_size: event.response_body_size
    }
  end

  defp error_category(%{error_message: message}) when is_binary(message),
    do: Helpers.error_category(message)

  defp error_category(_event), do: nil

  defp timing(nil), do: nil

  defp timing(event) do
    Map.take(event, [
      :latency_us,
      :queue_us,
      :connect_us,
      :request_send_us,
      :ttfb_us,
      :response_duration_us
    ])
  end
end
