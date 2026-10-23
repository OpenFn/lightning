defmodule LightningWeb.ChannelHelpers do
  @moduledoc """
  Helper functions for channels
  """

  import LightningWeb.CoreComponents, only: [translate_error: 1]

  @doc """
  Replies, and reports an error reply to Sentry.

  Opt in only where an error means something unexpected happened, as on the
  worker-facing RunChannel. Errors a user can cause and act on belong in a
  plain `{:reply, {:error, ...}}`; see `.claude/rules/logging.md`.
  """

  def reply_and_report(socket, {:error, error}) do
    send_warning_to_sentry(socket, error)
    {:reply, {:error, error_to_map(error)}, socket}
  end

  def reply_and_report(socket, reply) do
    {:reply, reply, socket}
  end

  @doc """
  A changeset's errors as the channels send them, `%{field => [message]}`.
  ws-worker reads this shape.
  """
  @spec changeset_errors(Ecto.Changeset.t()) :: %{atom() => [String.t()]}
  def changeset_errors(%Ecto.Changeset{} = changeset),
    do: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)

  defp error_to_map(%Ecto.Changeset{} = error), do: changeset_errors(error)

  defp error_to_map(error), do: error

  defp send_warning_to_sentry(socket, error) do
    Lightning.Sentry.capture_message(
      "#{inspect(socket.channel)} replied with error",
      extra: %{error: inspect(error)},
      level: :warning
    )
  end
end
