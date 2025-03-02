defmodule Lightning.Credentials.Credential do
  @moduledoc """
  The Credential model.
  """
  use Lightning.Schema

  alias Lightning.Accounts.User
  alias Lightning.Credentials
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
    |> maybe_validate_oauth_fields(attrs)
  end

  defp maybe_validate_oauth_fields(changeset, attrs) do
    is_oauth = get_field(changeset, :schema) == "oauth"
    oauth_token_id = get_field(changeset, :oauth_token_id)

    if is_oauth && !oauth_token_id do
      user_id = get_field(changeset, :user_id)

      oauth_client_id = Map.get(attrs, "oauth_client_id")

      token_data = Map.get(attrs, "oauth_token")

      if is_nil(token_data) do
        add_error(
          changeset,
          :oauth_token,
          "OAuth credentials require token data"
        )
      else
        scopes =
          case OauthToken.extract_scopes(token_data) do
            {:ok, extracted_scopes} -> extracted_scopes
            :error -> []
          end

        case Credentials.validate_oauth_token_data(
               token_data,
               user_id,
               oauth_client_id,
               scopes
             ) do
          {:ok, _} -> changeset
          {:error, reason} -> add_error(changeset, :oauth_token, reason)
        end
      end
    else
      changeset
    end
  end
end
