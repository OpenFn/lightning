defmodule Lightning.Channels.ChannelSnapshot do
  @moduledoc """
  Schema for a ChannelSnapshot — an immutable point-in-time copy of a
  channel's configuration, created when a request is proxied.
  """
  use Lightning.Schema

  alias Lightning.Channels.Channel

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          channel_id: Ecto.UUID.t(),
          lock_version: integer(),
          name: String.t(),
          destination_url: String.t(),
          enabled: boolean(),
          inserted_at: DateTime.t()
        }

  schema "channel_snapshots" do
    field :lock_version, :integer
    field :name, :string
    field :destination_url, :string
    field :enabled, :boolean

    belongs_to :channel, Channel

    has_many :channel_requests, Lightning.Channels.ChannelRequest

    timestamps(updated_at: false)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :channel_id,
      :lock_version,
      :name,
      :destination_url,
      :enabled
    ])
    |> validate_required([
      :channel_id,
      :lock_version,
      :name,
      :destination_url,
      :enabled
    ])
    |> assoc_constraint(:channel)
    |> unique_constraint([:channel_id, :lock_version])
  end
end
