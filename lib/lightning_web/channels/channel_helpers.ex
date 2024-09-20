defmodule LightningWeb.ChannelHelpers do
  @moduledoc """
  Helper functions for channels
  """

  def reply_with(socket, {:error, error}) do
    send_error_to_sentry(socket, error)
    {:reply, {:error, error}, socket}
  end

  def reply_with(socket, reply) do
    {:reply, reply, socket}
  end

  defp send_error_to_sentry(socket, error) do
    error = "#{socket.channel}.Error"
    Sentry.capture_message(error, extra: %{error: error})
  end
end
