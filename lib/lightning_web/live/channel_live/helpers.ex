defmodule LightningWeb.ChannelLive.Helpers do
  @moduledoc """
  Shared helpers for channel LiveViews.
  """

  def channel_proxy_url(channel_id) do
    "#{LightningWeb.Endpoint.url()}/channels/#{channel_id}"
  end
end
