defmodule Lightning.Channels do
  @moduledoc """
  Context for managing Channels — HTTP proxy configurations that forward
  requests from a client to a destination.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Lightning.Accounts.User
  alias Lightning.Channels.Audit
  alias Lightning.Channels.Channel
  alias Lightning.Channels.ChannelEvent
  alias Lightning.Channels.ChannelRequest
  alias Lightning.Channels.ChannelSnapshot
  alias Lightning.Channels.SearchParams
  alias Lightning.Config
  alias Lightning.Projects.Project
  alias Lightning.Repo

  require Logger

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
  Returns a paginated page of ChannelRequest records for a project.

  Preloads `:channel` and `:channel_events`.

  ## Parameters
    - `project` — `%Project{}` struct; scopes results to this project
    - `search_params` — `%SearchParams{}`; currently supports `channel_id`
      filter
    - `params` — Scrivener page params map, e.g. `%{"page" => "2"}`
  """
  @spec list_channel_requests(
          Project.t(),
          SearchParams.t(),
          map()
        ) :: Scrivener.Page.t()
  def list_channel_requests(
        %Project{id: project_id},
        %SearchParams{} = search_params,
        params \\ %{}
      ) do
    events_query =
      from(e in ChannelEvent,
        where: e.type in [:destination_response, :error],
        order_by: [e.channel_request_id, e.inserted_at]
      )

    from(cr in ChannelRequest,
      join: c in assoc(cr, :channel),
      on: c.project_id == ^project_id,
      order_by: [desc: cr.started_at],
      preload: [channel: c, channel_events: ^events_query]
    )
    |> filter_by_channel(search_params)
    |> Repo.paginate(params)
  end

  defp filter_by_channel(query, %SearchParams{channel_id: nil}), do: query

  defp filter_by_channel(query, %SearchParams{channel_id: channel_id}) do
    where(query, [cr], cr.channel_id == ^channel_id)
  end

  @doc """
  Gets a single channel by ID. Returns `nil` if not found.

  ## Options

    * `:include` - list of associations to preload (default: `[]`)
  """
  def get_channel(id, opts \\ []) do
    channel_query(id, opts) |> Repo.one()
  end

  @doc """
  Gets a single channel by ID. Raises `Ecto.NoResultsError` if not found.

  Accepts the same options as `get_channel/2`.
  """
  def get_channel!(id, opts \\ []) do
    channel_query(id, opts) |> Repo.one!()
  end

  defp channel_query(id, opts) do
    preloads = Keyword.get(opts, :include, [])

    from(c in Channel, where: c.id == ^id)
    |> preload(^preloads)
  end

  @doc """
  Gets a channel by ID with all auth methods preloaded.

  Preloads client auth methods (with webhook_auth_method) and destination auth
  method (with project_credential → credential). Returns nil if not found.

  Used by ChannelProxyPlug for client authentication and destination credential resolution.
  """
  def get_channel_with_auth(id) do
    from(c in Channel,
      where: c.id == ^id,
      left_join: cli in assoc(c, :client_auth_methods),
      left_join: wam in assoc(cli, :webhook_auth_method),
      left_join: dest in assoc(c, :destination_auth_method),
      left_join: pc in assoc(dest, :project_credential),
      left_join: cred in assoc(pc, :credential),
      preload: [
        client_auth_methods: {cli, webhook_auth_method: wam},
        client_webhook_auth_methods: wam,
        destination_auth_method:
          {dest, project_credential: {pc, credential: cred}}
      ]
    )
    |> Repo.one()
  end

  @doc """
  Gets a channel by ID scoped to a project. Returns `nil` if the channel
  does not exist or belongs to a different project.
  """
  def get_channel_for_project(project_id, channel_id, opts \\ []) do
    channel_query(channel_id, opts)
    |> where([c], c.project_id == ^project_id)
    |> Repo.one()
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
    |> Multi.run(:audit, fn _repo, %{channel: channel} ->
      case Audit.event("created", channel.id, actor, changeset) do
        :no_changes -> {:ok, :no_changes}
        %Ecto.Changeset{} = audit_cs -> Repo.insert(audit_cs)
      end
    end)
    |> Audit.audit_auth_method_changes(changeset, actor)
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
    |> Multi.run(:audit, fn _repo, %{channel: updated} ->
      case Audit.event("updated", updated.id, actor, changeset) do
        :no_changes -> {:ok, :no_changes}
        %Ecto.Changeset{} = audit_cs -> Repo.insert(audit_cs)
      end
    end)
    |> Audit.audit_auth_method_changes(changeset, actor)
    |> Repo.transaction()
    |> case do
      {:ok, %{channel: channel}} -> {:ok, channel}
      {:error, :channel, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Deletes a channel.

  Explicitly deletes all channel_requests first (required because
  `channel_requests.channel_id` uses `on_delete: :restrict`). Channel
  events cascade automatically, and channel snapshots cascade via
  `on_delete: :delete_all` on `channel_snapshots.channel_id`.
  """
  @spec delete_channel(Channel.t(), actor: User.t()) ::
          {:ok, Channel.t()} | {:error, Ecto.Changeset.t()}
  def delete_channel(%Channel{} = channel, actor: %User{} = actor) do
    from(cr in ChannelRequest,
      where: cr.channel_id == ^channel.id,
      select: cr.id
    )
    |> batch_delete_requests()

    Multi.new()
    |> Multi.insert(:audit, Audit.event("deleted", channel.id, actor, %{}))
    |> Multi.delete(:channel, channel)
    |> Repo.transaction()
    |> case do
      {:ok, %{channel: channel}} -> {:ok, channel}
      {:error, :channel, changeset, _} -> {:error, changeset}
    end
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
          destination_url: channel.destination_url,
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

  @doc """
  Deletes channel_requests older than `period_days` for channels in the
  given project. Channel events are cascade-deleted by the database FK.

  After deletion, removes orphaned channel_snapshots that are no longer
  referenced by any request and are not the current version.
  """
  @spec delete_expired_requests(Ecto.UUID.t(), pos_integer()) :: :ok
  def delete_expired_requests(project_id, period_days)
      when is_binary(project_id) and is_integer(period_days) do
    request_count =
      expired_requests_query(project_id, period_days)
      |> batch_delete_requests()

    if request_count > 0 do
      Logger.info("Deleted expired channel requests for project #{project_id}")
    end

    {snapshot_count, _} = delete_unused_channel_snapshots(project_id)

    if snapshot_count > 0 do
      Logger.info(
        "Deleted #{snapshot_count} unused channel snapshots for project #{project_id}"
      )
    end

    :ok
  end

  @doc """
  Deletes ALL channel_requests for a project's channels.

  Used during project deletion to satisfy the RESTRICT FK constraint
  on `channel_requests.channel_id` before channels are cascade-deleted.
  """
  @spec delete_channel_requests_for_project(Project.t()) :: :ok
  def delete_channel_requests_for_project(%Project{id: project_id}) do
    from(cr in ChannelRequest,
      join: c in Channel,
      on: cr.channel_id == c.id,
      where: c.project_id == ^project_id,
      select: cr.id
    )
    |> batch_delete_requests()

    :ok
  end

  defp batch_delete_requests(query) do
    batch_size = Config.activity_cleanup_chunk_size()

    total =
      Repo.aggregate(query, :count,
        timeout: Config.default_ecto_database_timeout() * 3
      )

    if total > 0 do
      delete_query =
        ChannelRequest
        |> with_cte("requests_to_delete",
          as: ^limit(query, ^batch_size)
        )
        |> join(:inner, [cr], rtd in "requests_to_delete", on: cr.id == rtd.id)

      Stream.iterate(0, &(&1 + 1))
      |> Stream.take(ceil(total / batch_size))
      |> Enum.each(fn _i ->
        {_count, _} =
          Repo.delete_all(delete_query,
            returning: false,
            timeout: Config.default_ecto_database_timeout() * 3
          )
      end)
    end

    total
  end

  defp expired_requests_query(project_id, period_days) do
    from(cr in ChannelRequest,
      join: c in Channel,
      on: cr.channel_id == c.id,
      where: c.project_id == ^project_id,
      where: cr.started_at < ago(^period_days, "day"),
      select: cr.id
    )
  end

  defp delete_unused_channel_snapshots(project_id) do
    batch_size = Config.activity_cleanup_chunk_size()

    unused_query =
      from(cs in ChannelSnapshot,
        as: :channel_snapshot,
        join: c in Channel,
        on: cs.channel_id == c.id,
        where: c.project_id == ^project_id,
        where: cs.lock_version != c.lock_version,
        where:
          not exists(
            from(cr in ChannelRequest,
              where:
                cr.channel_snapshot_id ==
                  parent_as(:channel_snapshot).id,
              select: 1
            )
          ),
        select: cs.id
      )

    total =
      Repo.aggregate(unused_query, :count,
        timeout: Config.default_ecto_database_timeout() * 3
      )

    if total > 0 do
      delete_query =
        ChannelSnapshot
        |> with_cte("snapshots_to_delete",
          as: ^limit(unused_query, ^batch_size)
        )
        |> join(:inner, [cs], std in "snapshots_to_delete", on: cs.id == std.id)

      Stream.iterate(0, &(&1 + 1))
      |> Stream.take(ceil(total / batch_size))
      |> Enum.each(fn _i ->
        {_count, _} =
          Repo.delete_all(delete_query,
            returning: false,
            timeout: Config.default_ecto_database_timeout() * 3
          )
      end)
    end

    {total, nil}
  end

  @doc """
  Returns a channel request with preloads, scoped to the given project.

  Returns `nil` if the request doesn't exist, belongs to a different project,
  or the ID is not a valid UUID.

  Preloads: `channel_events`, `channel`, `channel_snapshot`.
  """
  @spec get_channel_request_for_project(Ecto.UUID.t(), String.t()) ::
          ChannelRequest.t() | nil
  def get_channel_request_for_project(project_id, request_id) do
    case Ecto.UUID.cast(request_id) do
      {:ok, uuid} ->
        from(cr in ChannelRequest,
          join: c in Channel,
          on: cr.channel_id == c.id,
          where: cr.id == ^uuid and c.project_id == ^project_id,
          preload: [:channel_events, :channel, :channel_snapshot]
        )
        |> Repo.one()

      :error ->
        nil
    end
  end
end
