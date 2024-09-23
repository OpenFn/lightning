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
    Sentry.capture_message("#{socket.channel}.Error",
      extra: %{error: inspect(error)}
    )
  end
end
