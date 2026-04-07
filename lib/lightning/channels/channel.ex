defmodule Lightning.Channels.Channel do
  @moduledoc """
  Schema for a Channel — an HTTP proxy configuration that forwards
  requests from a client endpoint to a destination URL.
  """
  use Lightning.Schema

  alias Lightning.Channels.ChannelAuthMethod
  alias Lightning.Projects.Project
  alias Lightning.Validators

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          project_id: Ecto.UUID.t(),
          name: String.t(),
          destination_url: String.t(),
          enabled: boolean(),
          lock_version: integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "channels" do
    field :name, :string
    field :destination_url, :string
    field :enabled, :boolean, default: true
    field :lock_version, :integer, default: 0

    belongs_to :project, Project

    has_many :channel_auth_methods, ChannelAuthMethod

    has_many :client_auth_methods, ChannelAuthMethod, where: [role: :client]

    has_one :destination_auth_method, ChannelAuthMethod,
      where: [role: :destination],
      on_replace: :delete

    has_one :destination_credential,
      through: [:destination_auth_method, :project_credential]

    has_many :channel_snapshots, Lightning.Channels.ChannelSnapshot
    has_many :channel_requests, Lightning.Channels.ChannelRequest

    timestamps()
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [
      :name,
      :destination_url,
      :project_id,
      :enabled
    ])
    |> validate_required([:name, :destination_url, :project_id])
    |> Validators.validate_url(:destination_url)
    |> assoc_constraint(:project)
    |> unique_constraint([:project_id, :name],
      error_key: :name,
      message: "A channel with this name already exists in this project"
    )
    |> optimistic_lock(:lock_version)
    |> cast_assoc(:client_auth_methods,
      with: fn struct, attrs ->
        ChannelAuthMethod.changeset(struct, put_role(attrs, "client"))
      end
    )
    |> cast_assoc(:destination_auth_method,
      with: fn struct, attrs ->
        ChannelAuthMethod.changeset(struct, put_role(attrs, "destination"))
      end
    )
  end

  defp put_role(attrs, role) when is_map(attrs) do
    key = if has_string_keys?(attrs), do: "role", else: :role
    Map.put(attrs, key, role)
  end

  defp has_string_keys?(attrs) do
    attrs |> Map.keys() |> List.first() |> is_binary()
  end
end
