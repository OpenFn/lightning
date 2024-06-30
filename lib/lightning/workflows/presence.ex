defmodule Lightning.Workflows.Presence do
  use Phoenix.Presence,
    otp_app: :lightning,
    pubsub_server: Lightning.PubSub

  alias LightningWeb.Endpoint

  defstruct user: nil, joined_at: nil, priority: :low, active_sessions: 0

  @doc """
  Creates a new UserPresence struct.
  """
  def new_user_presence(user, joined_at, priority \\ :low, active_sessions \\ 0) do
    %__MODULE__{
      user: user,
      joined_at: joined_at,
      priority: priority,
      active_sessions: active_sessions
    }
  end

  @doc """
  Tracks the presence of a user on a given topic.
  """
  def track_user_presence(user, topic, pid) do
    joined_at = DateTime.utc_now() |> DateTime.to_unix()

    track(pid, topic, user.id, %{
      user: user,
      joined_at: joined_at
    })

    Endpoint.subscribe(topic)
  end

  @doc """
  Lists all presences for a given topic.
  """
  def list_presences(topic) do
    topic
    |> list_presences_by_topic()
    |> group_presences_by_user()
    |> assign_priorities_and_sessions()
  end

  defp list_presences_by_topic(topic) do
    list(topic)
    |> Enum.flat_map(fn {_user_id, %{metas: metas}} -> metas end)
  end

  defp group_presences_by_user(presences) do
    Enum.group_by(presences, & &1.user.id)
  end

  defp assign_priorities_and_sessions(grouped_presences) do
    grouped_presences
    |> Enum.map(fn {_id, group} ->
      active_sessions = length(group)

      new_user_presence(
        List.first(group).user,
        Enum.map(group, & &1.joined_at) |> Enum.min(),
        :low,
        active_sessions
      )
    end)
    |> Enum.sort_by(& &1.joined_at)
    |> Enum.with_index()
    |> Enum.map(fn {user_presence, index} ->
      if index == 0 do
        %{user_presence | priority: :high}
      else
        user_presence
      end
    end)
  end
end
