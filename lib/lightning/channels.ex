defmodule Lightning.Channels do
  @moduledoc """
  Context for managing Channels — HTTP proxy configurations that forward
  requests from a source to a sink.
  """

  import Ecto.Query

  alias Lightning.Channels.Channel
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
    |> Repo.update()
  end

  @doc """
  Deletes a channel.

  Returns `{:error, :has_history}` if the channel has snapshots
  referenced by requests (due to `:restrict` FK constraint).
  """
  def delete_channel(%Channel{} = channel) do
    Repo.delete(channel)
  rescue
    Ecto.ConstraintError -> {:error, :has_history}
  end
end
