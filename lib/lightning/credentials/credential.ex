defmodule Lightning.Credentials.Credential do
  @moduledoc """
  The Credential model.
  """
  use Lightning.Schema

  alias Lightning.Accounts.User
  alias Lightning.Credentials.OauthClient
  alias Lightning.Projects.ProjectCredential

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          body: nil | %{}
        }

  schema "credentials" do
    field :name, :string
    field :body, Lightning.Encrypted.Map, redact: true
    field :production, :boolean, default: false
    field :schema, :string
    field :scheduled_deletion, :utc_datetime

    belongs_to :user, User
    belongs_to :oauth_client, OauthClient

    has_many :project_credentials, ProjectCredential
    has_many :projects, through: [:project_credentials, :project]

    timestamps()
  end

  @doc false
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :name,
      :body,
      :production,
      :user_id,
      :oauth_client_id,
      :schema,
      :scheduled_deletion
    ])
    |> cast_assoc(:project_credentials)
    |> validate_required([:name, :body, :user_id])
    |> unique_constraint([:name, :user_id],
      message: "you have another credential with the same name"
    )
    |> assoc_constraint(:user)
    |> assoc_constraint(:oauth_client)
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\- ]*$/,
      message: "credential name has invalid format"
    )
    |> validate_oauth()
  end

  defp validate_oauth(changeset) do
    if get_field(changeset, :schema) == "oauth" do
      body = get_field(changeset, :body) || %{}

      body = Enum.into(body, %{}, fn {k, v} -> {to_string(k), v} end)

      required_fields = ["access_token", "refresh_token"]
      expires_fields = ["expires_in", "expires_at"]

      has_required_fields? = Enum.all?(required_fields, &Map.has_key?(body, &1))
      has_expires_field? = Enum.any?(expires_fields, &Map.has_key?(body, &1))

      if has_required_fields? and has_expires_field? do
        changeset
      else
        add_error(
          changeset,
          :body,
          "Invalid OAuth token. Missing required fields: access_token, refresh_token, and either expires_in or expires_at."
        )
      end
    else
      changeset
    end
  end
end
