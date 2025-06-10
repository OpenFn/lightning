defmodule LightningWeb.ChannelHelpers do
  @moduledoc """
  Helper functions for channels
  """

  def reply_with(socket, {:error, error}) do
    {:reply, {:error, error_to_map(error)}, socket}
  end

  def reply_with(socket, reply) do
    {:reply, reply, socket}
  end

  defp error_to_map(%Ecto.Changeset{} = error) do
    LightningWeb.ChangesetJSON.errors(error)
  end

  defp error_to_map(error), do: error
end
