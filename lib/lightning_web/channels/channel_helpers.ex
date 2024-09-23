defmodule LightningWeb.ChannelHelpers do
  @moduledoc """
  Helper functions for channels
  """

  def reply_with(socket, {:error, error}) do
    send_error_to_sentry(socket, error)
    {:reply, {:error, error_to_map(error)}, socket}
  end

  def reply_with(socket, reply) do
    {:reply, reply, socket}
  end

  defp error_to_map(%Ecto.Changeset{} = error) do
    LightningWeb.ChangesetJSON.error(error)
  end

  defp error_to_map(error), do: error

  defp send_error_to_sentry(socket, error) do
    Sentry.capture_message("#{socket.channel}.Error",
      extra: %{error: inspect(error)}
    )
  end
end
