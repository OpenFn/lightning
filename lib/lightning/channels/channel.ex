defmodule Lightning.Channels.Channel do
  use Lightning.Schema

  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectCredential

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          project_id: Ecto.UUID.t(),
          name: String.t(),
          sink_url: String.t(),
          source_project_credential_id: Ecto.UUID.t() | nil,
          sink_project_credential_id: Ecto.UUID.t() | nil,
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
    belongs_to :source_project_credential, ProjectCredential
    belongs_to :sink_project_credential, ProjectCredential

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
      :source_project_credential_id,
      :sink_project_credential_id,
      :enabled
    ])
    |> validate_required([:name, :sink_url, :project_id])
    |> assoc_constraint(:project)
    |> unique_constraint([:project_id, :name])
    |> optimistic_lock(:lock_version)
  end
end
