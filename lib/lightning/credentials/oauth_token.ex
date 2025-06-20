defmodule Lightning.Credentials.OauthToken do
  @moduledoc """
  Schema and functions for managing OAuth tokens. This module handles the storage and
  validation of OAuth tokens, allowing multiple credentials to share the same token
  when they have identical scope sets.
  """
  use Lightning.Schema

  alias Lightning.Accounts.User
  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.OauthClient
  alias Lightning.Credentials.OauthValidation

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          body: map(),
          scopes: [String.t()],
          oauth_client_id: Ecto.UUID.t() | nil,
          oauth_client: OauthClient.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          user: User.t() | nil,
          credentials: [Credential.t()] | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "oauth_tokens" do
    field :body, Lightning.Encrypted.Map, redact: true
    field :scopes, {:array, :string}

    field :oauth_error_type, :string, virtual: true
    field :oauth_error_details, :map, virtual: true

    belongs_to :oauth_client, OauthClient
    belongs_to :user, User
    has_many :credentials, Credential

    timestamps()
  end

  @doc """
  Creates a changeset for validating and creating an OAuth token.

  ## Parameters

  - `attrs` - A map containing token attributes:
    - `:body` - The token data (required)
    - `:scopes` - List of permission scopes for the token (required)
    - `:oauth_client_id` - Reference to the OAuth client (required)
    - `:user_id` - Reference to the user (required)

  ## Validations

  - All fields are required
  - Referenced oauth_client and user must exist
  - Token body must be valid (via validate_oauth_body/1)

  ## Examples

      iex> OauthToken.changeset(%{
      ...>   body: %{"access_token" => "abc123", "refresh_token" => "xyz789"},
      ...>   scopes: ["read", "write"],
      ...>   oauth_client_id: client.id,
      ...>   user_id: user.id
      ...> })
      #Ecto.Changeset<...>
  """
  def changeset(attrs), do: changeset(%__MODULE__{}, attrs)

  def changeset(oauth_token, attrs) do
    oauth_token
    |> cast(attrs, [:body, :scopes, :oauth_client_id, :user_id])
    |> validate_required([:body, :scopes, :oauth_client_id, :user_id])
    |> assoc_constraint(:oauth_client)
    |> assoc_constraint(:user)
    |> validate_oauth_body()
  end

  defdelegate extract_scopes(token_data),
    to: Lightning.Credentials.OauthValidation

  @doc """
  Creates a changeset for updating token data.
  Only merges with existing token body if new_token is a map, otherwise uses new_token directly.
  Preserves the refresh_token from the existing token.
  """
  def update_token_changeset(oauth_token, new_token) do
    scopes =
      case OauthValidation.extract_scopes(new_token) do
        {:ok, scopes} -> scopes
        :error -> nil
      end

    body = ensure_refresh_token(oauth_token, new_token)

    oauth_token
    |> cast(%{body: body, scopes: scopes}, [:body, :scopes])
    |> validate_required([:body, :scopes])
    |> validate_oauth_body()
  end

  defp ensure_refresh_token(
         %__MODULE__{body: %{"refresh_token" => refresh_token}},
         new_token
       )
       when is_map(new_token) do
    Map.merge(%{"refresh_token" => refresh_token}, new_token)
  end

  defp validate_oauth_body(changeset) do
    with {_, body} <- fetch_field(changeset, :body), true <- is_map(body) do
      %{user_id: user_id, oauth_client_id: oauth_client_id, scopes: scopes} =
        get_fields(changeset, [:user_id, :oauth_client_id, :scopes])

      case OauthValidation.validate_token_data(
             body,
             user_id,
             oauth_client_id,
             scopes
           ) do
        {:ok, _} ->
          changeset

        {:error, %OauthValidation.Error{} = error} ->
          add_oauth_error(changeset, error)
      end
    else
      _ ->
        error =
          OauthValidation.Error.new(
            :invalid_token_format,
            "Invalid OAuth token body"
          )

        add_oauth_error(changeset, error)
    end
  end

  defp add_oauth_error(
         changeset,
         %Lightning.Credentials.OauthValidation.Error{} = error
       ) do
    changeset
    |> add_error(:body, error.message)
    |> put_change(:oauth_error_type, error.type)
    |> put_change(:oauth_error_details, error.details)
  end

  defp get_fields(changeset, fields) when is_list(fields) do
    Enum.reduce(fields, %{}, fn field, acc ->
      Map.put(acc, field, get_field(changeset, field))
    end)
  end
end
