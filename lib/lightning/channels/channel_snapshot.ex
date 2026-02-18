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
          sink_url: String.t(),
          sink_project_credential_id: Ecto.UUID.t() | nil,
          sink_credential_name: String.t() | nil,
          enabled: boolean(),
          inserted_at: DateTime.t()
        }

  schema "channel_snapshots" do
    field :lock_version, :integer
    field :name, :string
    field :sink_url, :string
    field :sink_project_credential_id, Ecto.UUID
    field :sink_credential_name, :string
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
      :sink_url,
      :sink_project_credential_id,
      :sink_credential_name,
      :enabled
    ])
    |> validate_required([
      :channel_id,
      :lock_version,
      :name,
      :sink_url,
      :enabled
    ])
    |> assoc_constraint(:channel)
    |> unique_constraint([:channel_id, :lock_version])
  end
end
