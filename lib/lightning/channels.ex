defmodule Lightning.Channels do
  @moduledoc """
  Context for managing Channels — HTTP proxy configurations that forward
  requests from a source to a sink.
  """

  import Ecto.Query

  alias Lightning.Channels.Channel
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
  Gets a single channel by ID. Returns nil if not found.
  """
  def get_channel(id) do
    Repo.get(Channel, id)
  end

  @doc """
  Gets a single channel. Raises if not found.
  """
  def get_channel!(id) do
    Repo.get!(Channel, id)
  end

  @doc """
  Creates a channel.
  """
  def create_channel(attrs) do
    %Channel{}
    |> Channel.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a channel's config fields, bumping lock_version.
  """
  def update_channel(%Channel{} = channel, attrs) do
    channel
    |> Channel.changeset(attrs)
    |> Repo.update(stale_error_field: :lock_version)
  end

  @doc """
  Deletes a channel.

  Returns `{:error, changeset}` if the channel has snapshots
  (due to `:restrict` FK on `channel_snapshots`).
  """
  def delete_channel(%Channel{} = channel) do
    channel
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.foreign_key_constraint(:channel_snapshots,
      name: "channel_snapshots_channel_id_fkey",
      message: "has history that must be retained"
    )
    |> Repo.delete()
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
          enabled: channel.enabled,
          sink_project_credential_id: channel.sink_project_credential_id
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
