defmodule Lightning.Channels do
  @moduledoc """
  Context for managing Channels — HTTP proxy configurations that forward
  requests from a source to a sink.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Lightning.Accounts.User
  alias Lightning.Channels.Audit
  alias Lightning.Channels.Channel
  alias Lightning.Channels.ChannelAuthMethod
  alias Lightning.Channels.ChannelRequest
  alias Lightning.Channels.ChannelSnapshot
  alias Lightning.Repo

  @doc """
  Returns all channels for a project, ordered by name.
  """
  def list_channels_for_project(project_id) do
    from(c in Channel,
      where: c.project_id == ^project_id,
      order_by: [asc: :name]
    )
    |> Repo.all()
  end

  @doc """
  Returns channels for a project with aggregate stats from channel_requests.

  Each entry is a map with keys:
    - all Channel fields (via struct)
    - `:request_count` — total number of requests
    - `:last_activity` — datetime of most recent request, or nil
  """
  def list_channels_for_project_with_stats(project_id) do
    from(c in Channel,
      where: c.project_id == ^project_id,
      left_join: cr in ChannelRequest,
      on: cr.channel_id == c.id,
      group_by: c.id,
      order_by: [asc: c.name],
      select: %{
        channel: c,
        request_count: count(cr.id),
        last_activity: max(cr.started_at)
      }
    )
    |> Repo.all()
  end

  @doc """
  Returns aggregate stats for all channels in a project.

  Returns a map with:
    - `:total_channels` — number of channels in the project
    - `:total_requests` — total channel requests across all channels

  Uses a single query with a LEFT JOIN so both counts are fetched in one
  database round-trip.
  """
  def get_channel_stats_for_project(project_id) do
    from(c in Channel,
      where: c.project_id == ^project_id,
      left_join: cr in ChannelRequest,
      on: cr.channel_id == c.id,
      select: %{
        total_channels: count(c.id, :distinct),
        total_requests: count(cr.id)
      }
    )
    |> Repo.one()
  end

  @doc """
  Gets a single channel by ID. Returns nil if not found.
  """
  def get_channel(id) do
    Repo.get(Channel, id)
  end

  @doc """
  Gets a channel by ID with all auth methods preloaded.

  Preloads source auth methods (with webhook_auth_method) and sink auth
  methods (with project_credential → credential). Returns nil if not found.

  Used by ChannelProxyPlug for source authentication and sink credential resolution.
  """
  def get_channel_with_auth(id) do
    from(c in Channel,
      where: c.id == ^id,
      left_join: src in assoc(c, :source_auth_methods),
      left_join: wam in assoc(src, :webhook_auth_method),
      left_join: snk in assoc(c, :sink_auth_methods),
      left_join: pc in assoc(snk, :project_credential),
      left_join: cred in assoc(pc, :credential),
      preload: [
        source_auth_methods: {src, webhook_auth_method: wam},
        sink_auth_methods: {snk, project_credential: {pc, credential: cred}}
      ]
    )
    |> Repo.one()
  end

  @doc """
  Gets a single channel. Raises if not found.
  """
  def get_channel!(id, opts \\ []) do
    preloads = Keyword.get(opts, :include, [])
    Repo.get!(Channel, id) |> Repo.preload(preloads)
  end

  @doc """
  Creates a channel.
  """
  @spec create_channel(map(), actor: User.t()) ::
          {:ok, Channel.t()} | {:error, Ecto.Changeset.t()}
  def create_channel(attrs, actor: %User{} = actor) do
    changeset = Channel.changeset(%Channel{}, attrs)

    Multi.new()
    |> Multi.insert(:channel, changeset)
    |> Multi.insert(:audit, fn %{channel: channel} ->
      Audit.event("created", channel.id, actor, changeset)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{channel: channel}} -> {:ok, channel}
      {:error, :channel, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Updates a channel's config fields, bumping lock_version.
  """
  @spec update_channel(Channel.t(), map(), actor: User.t()) ::
          {:ok, Channel.t()} | {:error, Ecto.Changeset.t()}
  def update_channel(%Channel{} = channel, attrs, actor: %User{} = actor) do
    changeset = Channel.changeset(channel, attrs)

    Multi.new()
    |> Multi.update(:channel, changeset, stale_error_field: :lock_version)
    |> Multi.insert(:audit, fn %{channel: updated} ->
      Audit.event("updated", updated.id, actor, changeset)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{channel: channel}} -> {:ok, channel}
      {:error, :channel, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Deletes a channel.

  Returns `{:error, changeset}` if the channel has snapshots
  (due to `:restrict` FK on `channel_snapshots`).
  """
  @spec delete_channel(Channel.t(), actor: User.t()) ::
          {:ok, Channel.t()} | {:error, Ecto.Changeset.t()}
  def delete_channel(%Channel{} = channel, actor: %User{} = actor) do
    changeset =
      channel
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.foreign_key_constraint(:channel_snapshots,
        name: "channel_snapshots_channel_id_fkey",
        message: "has history that must be retained"
      )

    Multi.new()
    |> Multi.insert(:audit, Audit.event("deleted", channel.id, actor, %{}))
    |> Multi.delete(:channel, changeset)
    |> Repo.transaction()
    |> case do
      {:ok, %{channel: channel}} -> {:ok, channel}
      {:error, :channel, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Returns all ChannelAuthMethod records for a channel, preloading
  their associated webhook_auth_method and project_credential (with credential).
  """
  def list_channel_auth_methods(%Channel{} = channel) do
    from(cam in ChannelAuthMethod,
      where: cam.channel_id == ^channel.id,
      preload: [:webhook_auth_method, project_credential: :credential]
    )
    |> Repo.all()
  end

  @doc """
  Get or create a snapshot for the channel's current lock_version.

  Returns an existing snapshot if one matches, or creates a minimal one from
  the current channel config. Handles concurrent creation race via
  ON CONFLICT DO NOTHING + re-fetch.

  Full snapshot lifecycle management is in #4406.
  """
  def get_or_create_current_snapshot(%Channel{} = channel) do
    case Repo.get_by(ChannelSnapshot,
           channel_id: channel.id,
           lock_version: channel.lock_version
         ) do
      %ChannelSnapshot{} = snapshot ->
        {:ok, snapshot}

      nil ->
        attrs = %{
          channel_id: channel.id,
          lock_version: channel.lock_version,
          name: channel.name,
          sink_url: channel.sink_url,
          enabled: channel.enabled
        }

        %ChannelSnapshot{}
        |> ChannelSnapshot.changeset(attrs)
        |> Repo.insert(
          on_conflict: :nothing,
          conflict_target: [:channel_id, :lock_version]
        )
        |> case do
          {:ok, %ChannelSnapshot{id: nil}} ->
            # ON CONFLICT DO NOTHING returns struct with nil id; re-fetch
            snapshot =
              Repo.get_by!(ChannelSnapshot,
                channel_id: channel.id,
                lock_version: channel.lock_version
              )

            {:ok, snapshot}

          {:ok, snapshot} ->
            {:ok, snapshot}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end
end
