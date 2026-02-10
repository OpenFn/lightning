defmodule Lightning.Channels.ChannelSnapshot do
  use Lightning.Schema

  alias Lightning.Channels.Channel

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          channel_id: Ecto.UUID.t(),
          lock_version: integer(),
          name: String.t(),
          sink_url: String.t(),
          source_project_credential_id: Ecto.UUID.t() | nil,
          source_credential_name: String.t() | nil,
          sink_project_credential_id: Ecto.UUID.t() | nil,
          sink_credential_name: String.t() | nil,
          enabled: boolean(),
          inserted_at: DateTime.t()
        }

  schema "channel_snapshots" do
    field :lock_version, :integer
    field :name, :string
    field :sink_url, :string
    field :source_project_credential_id, Ecto.UUID
    field :source_credential_name, :string
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
      :source_project_credential_id,
      :source_credential_name,
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
