defmodule Lightning.AuthProviders.AuthConfig do
  @moduledoc """
  AuthProvider model
  """
  use Lightning.Schema

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          client_id: String.t() | nil,
          client_secret: String.t() | nil,
          discovery_url: String.t() | nil,
          redirect_uri: String.t() | nil,
          allow_unverified_email: boolean()
        }

  schema "auth_providers" do
    field :name, :string

    field :client_id, :string
    field :client_secret, :string
    field :discovery_url, :string
    field :redirect_uri, :string

    # Trust this provider's email even when it doesn't assert `email_verified`.
    # Off by default: only enable for a provider you trust (e.g. a single-tenant
    # IdP that omits the claim), since a self-asserted email would otherwise be
    # taken at face value.
    field :allow_unverified_email, :boolean, default: false

    timestamps()
  end

  @required_fields [
    :name,
    :client_id,
    :client_secret,
    :discovery_url,
    :redirect_uri
  ]

  @optional_fields [:allow_unverified_email]

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
