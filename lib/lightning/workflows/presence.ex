defmodule Lightning.Workflows.Presence do
  @moduledoc """
  Handles user presence tracking within the Workflow canvas page.

  This module leverages Phoenix.Presence to track user sessions, manage user priorities,
  and list active presences on specified topics.
  """
  use Phoenix.Presence,
    otp_app: :lightning,
    pubsub_server: Lightning.PubSub

  alias LightningWeb.Endpoint

  defstruct user: nil, joined_at: nil, priority: :low, active_sessions: 0

  @doc """
  Creates a new `UserPresence` struct.

  ## Parameters

    - `user`: The user data to be included in the presence.
    - `joined_at`: The timestamp when the user joined, in microseconds.
    - `priority`: The priority level of the user presence (default is `:low`).
    - `active_sessions`: The number of active sessions for the user (default is 0).

  ## Examples

      iex> Lightning.Workflows.Presence.new_user_presence(%User{id: 1}, 1625597762000000)
      %Lightning.Workflows.Presence{
        user: %User{id: 1},
        joined_at: 1625597762000000,
        priority: :low,
        active_sessions: 0
      }

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

  ## Parameters

    - `user`: The user to be tracked.
    - `topic`: The topic to track the user on.
    - `pid`: The process identifier for the user's session.

  ## Examples

      iex> Lightning.Workflows.Presence.track_user_presence(%User{id: 1}, "room:lobby", self())
      :ok

  """
  def track_user_presence(user, topic, pid) do
    joined_at = System.system_time(:microsecond)

    track(pid, topic, user.id, %{
      user: user,
      joined_at: joined_at
    })

    Endpoint.subscribe(topic)
  end

  @doc """
  Lists all presences for a given topic.

  ## Parameters

    - `topic`: The topic to list the presences for.

  ## Examples

      iex> Lightning.Workflows.Presence.list_presences("workflow:canvas")
      [%Lightning.Workflows.Presence{user: %User{id: 1}, ...}, ...]

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
      presence = List.first(group)

      new_user_presence(
        presence.user,
        presence.joined_at,
        :low,
        active_sessions
      )
    end)
  end
end
