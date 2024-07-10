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

  defstruct user: nil, joined_at: nil, active_sessions: 0

  @doc """
  Creates a new `UserPresence` struct.

  ## Parameters

    - `user`: The user data to be included in the presence.
    - `joined_at`: The timestamp when the user joined, in microseconds.
    - `active_sessions`: The number of active sessions for the user (default is 0).

  ## Examples

      iex> Lightning.Workflows.Presence.new_user_presence(%User{id: 1}, 1625597762000000)
      %Lightning.Workflows.Presence{
        user: %User{id: 1},
        joined_at: 1625597762000000,
        active_sessions: 0
      }

  """
  def new_user_presence(user, joined_at, active_sessions \\ 0) do
    %__MODULE__{
      user: user,
      joined_at: joined_at,
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
    |> extract_presences()
  end

  @doc """
  Builds a summary of presences with details about the current user's presence, promotable presences,
  and edit priority.

  ## Parameters

    - `presences` (list): A list of presence records, each containing user information and a joined_at timestamp.
    - `params` (map): A map containing the following keys:
      - `:current_user_presence` - The presence record for the current user.
      - `:current_user` - The current user record.
      - `:view_only_users_ids` - A list of user IDs who have view-only permissions.

  ## Returns

    - `map`: A map containing the following keys:
      - `:presences` - The sorted list of all presences.
      - `:prior_user_presence` - The presence record with edit priority.
      - `:current_user_presence` - The presence record for the current user.
      - `:has_presence_edit_priority` - A boolean indicating if the current user has edit priority.

  ## Examples

      iex> presences = [
      ...>   %{user: %{id: 1}, joined_at: ~N[2024-07-03 12:00:00], active_sessions: 1},
      ...>   %{user: %{id: 2}, joined_at: ~N[2024-07-03 12:05:00], active_sessions: 1},
      ...>   %{user: %{id: 3}, joined_at: ~N[2024-07-03 12:10:00], active_sessions: 1}
      ...> ]
      iex> params = %{
      ...>   current_user_presence: %{user: %{id: 1}, joined_at: ~N[2024-07-03 12:00:00], active_sessions: 1},
      ...>   current_user: %{id: 1},
      ...>   view_only_users_ids: [2]
      ...> }
      iex> build_presences_summary(presences, params)
      %{
        presences: [
          %{user: %{id: 1}, joined_at: ~N[2024-07-03 12:00:00], active_sessions: 1},
          %{user: %{id: 2}, joined_at: ~N[2024-07-03 12:05:00], active_sessions: 1},
          %{user: %{id: 3}, joined_at: ~N[2024-07-03 12:10:00], active_sessions: 1}
        ],
        prior_user_presence: %{user: %{id: 3}, joined_at: ~N[2024-07-03 12:10:00], active_sessions: 1},
        current_user_presence: %{user: %{id: 1}, joined_at: ~N[2024-07-03 12:00:00], active_sessions: 1},
        has_presence_edit_priority: true
      }

  """
  def build_presences_summary(presences, params) do
    %{
      current_user_presence: current_user_presence,
      current_user: current_user,
      view_only_users_ids: view_only_users_ids
    } = params

    presences = Enum.sort_by(presences, & &1.joined_at)

    current_user_presence =
      Enum.find(presences, current_user_presence, fn presence ->
        presence.user.id == current_user.id
      end)

    presences_promotable =
      Enum.reject(presences, fn presence ->
        presence.user.id in view_only_users_ids
      end)

    prior_user_presence =
      if length(presences_promotable) > 0 do
        List.first(presences_promotable)
      else
        current_user_presence
      end

    has_presence_edit_priority =
      current_user_presence.user.id == prior_user_presence.user.id &&
        current_user_presence.active_sessions <= 1

    %{
      presences: presences,
      prior_user_presence: prior_user_presence,
      current_user_presence: current_user_presence,
      has_presence_edit_priority: has_presence_edit_priority
    }
  end

  defp list_presences_by_topic(topic) do
    list(topic)
    |> Enum.flat_map(fn {_user_id, %{metas: metas}} -> metas end)
  end

  defp group_presences_by_user(presences) do
    Enum.group_by(presences, & &1.user.id)
  end

  defp extract_presences(grouped_presences) do
    grouped_presences
    |> Enum.map(fn {_id, group} ->
      active_sessions = length(group)
      presence = List.first(group)

      new_user_presence(
        presence.user,
        presence.joined_at,
        active_sessions
      )
    end)
  end
end
