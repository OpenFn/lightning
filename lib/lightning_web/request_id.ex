defmodule LightningWeb.RequestId do
  @moduledoc """
  Carries the page load's `Plug.RequestId` into LiveView and channel
  processes, so their logs and Sentry events share it with the page load and
  the browser's own Sentry events.

  Websocket processes never pass through `Plug.RequestId`, so the browser
  sends the ID back as the `request_id` connect param. A tab keeps the same ID
  until its next full page load.
  """
  import Phoenix.LiveView, only: [connected?: 1, get_connect_params: 1]

  require Logger

  @doc """
  Returns the `request_id` param when it has the length `Plug.RequestId`
  accepts and only URL-safe characters, and `nil` otherwise. The value comes
  from the browser and ends up in log lines.
  """
  def parse(%{"request_id" => id})
      when is_binary(id) and byte_size(id) in 20..200 do
    if id =~ ~r/\A[A-Za-z0-9_\-+\/=.:]+\z/, do: id
  end

  def parse(_params), do: nil

  def on_mount(:default, _params, _session, socket) do
    # Connect params only reach the root LiveView.
    if connected?(socket) and is_nil(socket.parent_pid) do
      Logger.metadata(request_id: parse(get_connect_params(socket)))
    end

    {:cont, socket}
  end
end
