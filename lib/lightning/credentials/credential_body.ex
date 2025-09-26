defmodule Lightning.Credentials.CredentialBody do
  @moduledoc """
  Per-environment credential body storage.

  Each credential can have multiple environment variants (e.g., "main", "staging", "prod")
  with different configuration values.
  """
  use Lightning.Schema

  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.OauthToken

  schema "credential_bodies" do
    field :name, :string
    field :body, Lightning.Encrypted.Map, redact: true

    belongs_to :credential, Credential
    has_one :oauth_token, OauthToken, foreign_key: :credential_body_id

    timestamps()
  end

  def changeset(credential_body, attrs) do
    credential_body
    |> cast(attrs, [:name, :body, :credential_id])
    |> validate_required([:name, :body, :credential_id])
    |> validate_format(:name, ~r/^[a-z0-9][a-z0-9_-]{0,31}$/,
      message: "must be a short slug"
    )
    |> unique_constraint([:credential_id, :name])
    |> assoc_constraint(:credential)
  end
end
