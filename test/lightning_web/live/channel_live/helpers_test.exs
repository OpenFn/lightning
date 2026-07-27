defmodule LightningWeb.ChannelLive.HelpersTest do
  use ExUnit.Case, async: true

  alias LightningWeb.ChannelLive.Helpers

  describe "channel_proxy_url/1" do
    test "returns the full URL for a channel" do
      id = Ecto.UUID.generate()
      url = Helpers.channel_proxy_url(id)

      assert url == "#{LightningWeb.Endpoint.url()}/channels/#{id}"
    end
  end
end
