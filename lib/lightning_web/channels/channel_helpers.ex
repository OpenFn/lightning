defmodule LightningWeb.ChannelHelpers do
  @moduledoc """
  Helper functions for channels
  """

  def reply_with(socket, {:error, error}) do
    send_warning_to_sentry(error)
    {:reply, {:error, error_to_map(error)}, socket}
  end

  def reply_with(socket, reply) do
    {:reply, reply, socket}
  end

  defp error_to_map(%Ecto.Changeset{} = error) do
    LightningWeb.ChangesetJSON.errors(error)
  end

  defp error_to_map(error), do: error

  defp send_warning_to_sentry(error) do
    Sentry.capture_message("RunChannel replied with error",
      extra: %{error: inspect(error)},
      level: :warning
    )
  end
end
