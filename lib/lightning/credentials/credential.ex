defmodule Lightning.Credentials.Credential do
  @moduledoc """
  The Credential model.
  """
  use Lightning.Schema

  alias Lightning.Accounts.User
  alias Lightning.Credentials.OauthToken
  alias Lightning.Projects.ProjectCredential

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          body: nil | %{}
        }

  schema "credentials" do
    field :name, :string
    field :body, Lightning.Encrypted.Map, redact: true
    field :external_id, :string
    field :production, :boolean, default: false
    field :schema, :string
    field :scheduled_deletion, :utc_datetime
    field :transfer_status, Ecto.Enum, values: [:pending, :completed]

    belongs_to :user, User
    belongs_to :oauth_token, OauthToken

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
      :body,
      :external_id,
      :production,
      :user_id,
      :oauth_token_id,
      :schema,
      :scheduled_deletion,
      :transfer_status
    ])
    |> cast_assoc(:project_credentials)
    |> validate_required([:name, :body, :user_id])
    |> unique_constraint([:name, :user_id],
      message: "you have another credential with the same name"
    )
    |> assoc_constraint(:user)
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\- ]*$/,
      message: "credential name has invalid format"
    )
  end
end
