defmodule Lightning.Credentials.Credential do
  @moduledoc """
  The Credential model.
  Stores metadata about credentials. Actual credential data lives in credential_bodies.
  """
  use Lightning.Schema

  alias Lightning.Accounts.User
  alias Lightning.Credentials.OauthClient
  alias Lightning.Projects.ProjectCredential

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          name: String.t(),
          schema: String.t() | nil
        }

  schema "credentials" do
    field :name, :string
    field :external_id, :string
    field :schema, :string
    field :scheduled_deletion, :utc_datetime
    field :transfer_status, Ecto.Enum, values: [:pending, :completed]

    belongs_to :user, User
    belongs_to :oauth_client, OauthClient

    has_many :project_credentials, ProjectCredential
    has_many :projects, through: [:project_credentials, :project]
    has_many :credential_bodies, Lightning.Credentials.CredentialBody

    timestamps()
  end

  @doc false
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :name,
      :external_id,
      :user_id,
      :oauth_client_id,
      :schema,
      :scheduled_deletion,
      :transfer_status
    ])
    |> cast_assoc(:project_credentials)
    |> validate_required([:name, :user_id])
    |> unique_constraint([:name, :user_id],
      message: "you have another credential with the same name"
    )
    |> unique_constraint([:external_id, :user_id],
      message: "you already have a credential with the same external ID"
    )
    |> assoc_constraint(:user)
    |> assoc_constraint(:oauth_client)
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\- ]*$/,
      message: "credential name has invalid format"
    )
  end
end
