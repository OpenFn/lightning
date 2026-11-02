defmodule LightningWeb.API.ChannelJSON do
  @moduledoc """
  Renders a project's channels, each from an entry carrying the channel with
  its auth methods preloaded, its `request_count` and its `last_activity`.
  """
  import LightningWeb.API.Helpers

  def index(conn, page, totals) do
    %{
      data: Enum.map(page.entries, &resource/1),
      links: pagination_links(conn, page, %{}),
      meta: %{
        total_channels: totals.total_channels,
        total_requests: totals.total_requests
      }
    }
  end

  def show(entry), do: %{data: resource(entry)}

  defp resource(%{channel: channel} = entry) do
    base = LightningWeb.Endpoint.url()

    %{
      type: "channels",
      id: channel.id,
      attributes: %{
        name: channel.name,
        destination_url: channel.destination_url,
        enabled: channel.enabled,
        lock_version: channel.lock_version,
        url: "#{base}/channels/#{channel.id}",
        client_auth_method_ids:
          channel.client_auth_methods
          |> Enum.map(& &1.webhook_auth_method_id)
          |> Enum.sort(),
        destination_credential_id:
          destination_credential_id(channel.destination_auth_method),
        request_count: entry.request_count,
        last_activity: entry.last_activity,
        inserted_at: channel.inserted_at,
        updated_at: channel.updated_at
      },
      relationships: %{},
      links: %{
        self: "#{base}/api/projects/#{channel.project_id}/channels/#{channel.id}"
      }
    }
  end

  defp destination_credential_id(nil), do: nil

  defp destination_credential_id(%{project_credential: project_credential}),
    do: project_credential.credential_id
end
