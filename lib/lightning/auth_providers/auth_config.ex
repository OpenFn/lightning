defmodule Lightning.AuthProviders.AuthConfig do
  @moduledoc """
  AuthProvider model
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          client_id: String.t() | nil,
          client_secret: String.t() | nil,
          discovery_url: String.t() | nil,
          redirect_uri: String.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "auth_providers" do
    field :name, :string

    field :client_id, :string
    field :client_secret, :string
    field :discovery_url, :string
    field :redirect_uri, :string

    timestamps()
  end

  @fields [
    :name,
    :client_id,
    :client_secret,
    :discovery_url,
    :redirect_uri
  ]

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, @fields)
    |> validate_required(@fields)
  end
end
