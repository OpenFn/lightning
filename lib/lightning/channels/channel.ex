defmodule Lightning.Channels.Channel do
  @moduledoc """
  Schema for a Channel — an HTTP proxy configuration that forwards
  requests from a source endpoint to a sink URL.
  """
  use Lightning.Schema

  alias Lightning.Projects.Project
  alias Lightning.Validators

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          project_id: Ecto.UUID.t(),
          name: String.t(),
          sink_url: String.t(),
          enabled: boolean(),
          lock_version: integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "channels" do
    field :name, :string
    field :sink_url, :string
    field :enabled, :boolean, default: true
    field :lock_version, :integer, default: 0

    belongs_to :project, Project

    has_many :channel_auth_methods, Lightning.Channels.ChannelAuthMethod

    has_many :source_auth_methods, Lightning.Channels.ChannelAuthMethod,
      where: [role: :source]

    has_many :sink_auth_methods, Lightning.Channels.ChannelAuthMethod,
      where: [role: :sink]

    has_many :channel_snapshots, Lightning.Channels.ChannelSnapshot
    has_many :channel_requests, Lightning.Channels.ChannelRequest

    timestamps()
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [
      :name,
      :sink_url,
      :project_id,
      :enabled
    ])
    |> validate_required([:name, :sink_url, :project_id])
    |> Validators.validate_url(:sink_url)
    |> assoc_constraint(:project)
    |> unique_constraint([:project_id, :name])
    |> optimistic_lock(:lock_version)
    |> cast_assoc(:channel_auth_methods)
  end
end
