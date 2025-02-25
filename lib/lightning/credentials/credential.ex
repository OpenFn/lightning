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
    field :production, :boolean, default: false
    field :schema, :string
    field :scheduled_deletion, :utc_datetime
    field :transfer_status, Ecto.Enum, values: [:pending, :completed]

    field :oauth_client_id, :binary_id, virtual: true
    field :oauth_client, :any, virtual: true

    belongs_to :user, User
    belongs_to :oauth_token, OauthToken

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

  @doc """
  Gets the oauth_client_id for a credential by checking its oauth_token.
  """
  def oauth_client_id(%__MODULE__{oauth_token: %OauthToken{oauth_client_id: id}}),
    do: id

  def oauth_client_id(%__MODULE__{} = credential) do
    credential = Lightning.Repo.preload(credential, :oauth_token)
    oauth_client_id(credential)
  end

  @doc """
  Gets the oauth_client for a credential through its oauth_token.
  """
  def oauth_client(%__MODULE__{oauth_token: %OauthToken{oauth_client: client}})
      when not is_nil(client),
      do: client

  def oauth_client(%__MODULE__{} = credential) do
    credential = Lightning.Repo.preload(credential, oauth_token: :oauth_client)
    oauth_client(credential)
  end

  # defp validate_oauth(changeset) do
  #   if get_field(changeset, :schema) == "oauth" do
  #     body = get_field(changeset, :body) || %{}

  #     body = Enum.into(body, %{}, fn {k, v} -> {to_string(k), v} end)

  #     required_fields = ["access_token", "refresh_token"]
  #     expires_fields = ["expires_in", "expires_at"]

  #     has_required_fields? = Enum.all?(required_fields, &Map.has_key?(body, &1))
  #     has_expires_field? = Enum.any?(expires_fields, &Map.has_key?(body, &1))

  #     if has_required_fields? and has_expires_field? do
  #       changeset
  #     else
  #       add_error(
  #         changeset,
  #         :body,
  #         "Invalid OAuth token. Missing required fields: access_token, refresh_token, and either expires_in or expires_at."
  #       )
  #     end
  #   else
  #     changeset
  #   end
  # end
end
