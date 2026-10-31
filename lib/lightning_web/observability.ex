defmodule LightningWeb.Observability do
  @moduledoc """
  Identity and resource scope for the current process, shared by Logger and
  Sentry.

  Channels and LiveViews are processes, so calling `put_scope/1` once on join or
  mount covers everything that process later logs or captures.
  """

  @doc """
  Attaches scope to `Logger.metadata/1` and `Sentry.Context`.

  `:user_id` becomes the Sentry user, so events count towards "Users Impacted".
  Everything else becomes a Sentry tag, which is filterable and groupable where
  extra context is not.
  """
  @spec put_scope(keyword()) :: :ok
  def put_scope(scope) do
    Logger.metadata(scope)

    {user_id, rest} = Keyword.pop(scope, :user_id)

    if user_id, do: Sentry.Context.set_user_context(%{id: user_id})

    rest
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new(fn {k, v} -> {k, to_string(v)} end)
    |> Sentry.Context.set_tags_context()

    :ok
  end
end
