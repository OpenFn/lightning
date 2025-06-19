defmodule Lightning.Credentials.Credential do
  @moduledoc """
  The Credential model.
  """
  use Lightning.Schema

  alias Lightning.Accounts.User
  alias Lightning.Credentials.OAuthValidation
  alias Lightning.Credentials.OauthClient
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

    field :oauth_error_type, :string, virtual: true
    field :oauth_error_details, :map, virtual: true

    belongs_to :user, User
    belongs_to :oauth_token, OauthToken
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
    if oauth_credential?(changeset) do
      validate_oauth_fields(changeset, attrs)
    else
      changeset
    end
  end

  defp oauth_credential?(changeset) do
    get_field(changeset, :schema) == "oauth"
  end

  defp validate_oauth_fields(changeset, attrs) do
    creating_new_token? = is_nil(get_field(changeset, :oauth_token_id))
    token_data = Map.get(attrs, "oauth_token")

    case {creating_new_token?, token_data} do
      {true, nil} ->
        add_error(
          changeset,
          :oauth_token,
          "OAuth credentials require token data"
        )

      {_, token_data} when not is_nil(token_data) ->
        validate_oauth_token_and_scopes(
          changeset,
          token_data,
          attrs
        )

      {false, nil} ->
        changeset
    end
  end

  defp validate_oauth_token_and_scopes(
         changeset,
         token_data,
         attrs
       ) do
    user_id = get_field(changeset, :user_id)
    oauth_client_id = Map.get(attrs, "oauth_client_id")

    changeset
    |> validate_oauth_token_data(
      token_data,
      user_id,
      oauth_client_id
    )
    |> validate_oauth_scope_grant(token_data, attrs)
  end

  defp validate_oauth_token_data(changeset, token_data, user_id, oauth_client_id) do
    with {:ok, extracted_scopes} <- OAuthValidation.extract_scopes(token_data),
         {:ok, _} <-
           OAuthValidation.validate_token_data(
             token_data,
             user_id,
             oauth_client_id,
             extracted_scopes
           ) do
      changeset
    else
      :error ->
        error =
          OAuthValidation.Error.new(
            :invalid_token_format,
            "Invalid token format. Unable to extract scope information"
          )

        add_oauth_error(changeset, error)

      {:error, %OAuthValidation.Error{} = error} ->
        add_oauth_error(changeset, error)
    end
  end

  defp validate_oauth_scope_grant(changeset, token_data, attrs) do
    expected_scopes = Map.get(attrs, "expected_scopes", [])

    if Enum.empty?(expected_scopes) do
      changeset
    else
      case OAuthValidation.validate_scope_grant(token_data, expected_scopes) do
        :ok ->
          changeset

        {:error, %OAuthValidation.Error{} = error} ->
          add_oauth_error(changeset, error)
      end
    end
  end

  defp add_oauth_error(
         changeset,
         %Lightning.Credentials.OAuthValidation.Error{} = error
       ) do
    changeset
    |> add_error(:oauth_token, error.message)
    |> put_change(:oauth_error_type, error.type)
    |> put_change(:oauth_error_details, error.details)
  end
end
