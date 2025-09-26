defmodule Lightning.Credentials.OauthToken do
  @moduledoc """
  Schema and functions for managing OAuth tokens. This module handles the storage and
  validation of OAuth tokens in a 1:1 relationship with credentials.

  Each token contains all required OAuth 2.0 fields:
  - access_token (required)
  - refresh_token (required)
  - token_type (required, must be "Bearer")
  - scope/scopes (required)
  - expires_in/expires_at (required)

  Integrates with the enhanced OauthValidation module for comprehensive validation.
  """
  use Lightning.Schema

  alias Lightning.Accounts.User
  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.OauthClient
  alias Lightning.Credentials.OauthValidation

  @default_freshness_buffer_minutes 5

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          body: map(),
          scopes: [String.t()],
          last_refreshed: DateTime.t() | nil,
          oauth_client_id: Ecto.UUID.t() | nil,
          oauth_client: OauthClient.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          user: User.t() | nil,
          credential: Credential.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          credential_body_id: Ecto.UUID.t() | nil,
          credential_body: Lightning.Credentials.CredentialBody.t() | nil
        }

  schema "oauth_tokens" do
    field :body, Lightning.Encrypted.Map, redact: true
    field :scopes, {:array, :string}
    field :last_refreshed, :utc_datetime

    field :oauth_error_type, :string, virtual: true
    field :oauth_error_details, :map, virtual: true

    belongs_to :oauth_client, OauthClient
    belongs_to :user, User
    belongs_to :credential_body, Lightning.Credentials.CredentialBody

    has_one :credential, Credential

    timestamps()
  end

  @doc """
  Creates a changeset for validating and creating an OAuth token.

  ## Parameters

  - `attrs` - A map containing token attributes:
    - `:body` - The token data (required) - must include access_token, refresh_token, token_type, scope/scopes, expires_in/expires_at
    - `:scopes` - List of permission scopes for the token (optional, will be extracted from body if not provided)
    - `:oauth_client_id` - Reference to the OAuth client (required)
    - `:user_id` - Reference to the user (required)

  ## Validations

  - All required fields are validated
  - Referenced oauth_client and user must exist
  - Token body must contain valid OAuth 2.0 fields
  - Scopes are automatically extracted and normalized if not provided

  ## Examples

      iex> OauthToken.changeset(%{
      ...>   body: %{
      ...>     "access_token" => "abc123",
      ...>     "refresh_token" => "xyz789",
      ...>     "token_type" => "Bearer",
      ...>     "scope" => "read write",
      ...>     "expires_in" => 3600
      ...>   },
      ...>   oauth_client_id: client.id,
      ...>   user_id: user.id
      ...> })
      #Ecto.Changeset<...>
  """
  @spec changeset(t() | map(), map()) :: Ecto.Changeset.t()
  def changeset(attrs), do: changeset(%__MODULE__{}, attrs)

  def changeset(oauth_token, attrs) do
    oauth_token
    |> cast(attrs, [
      :body,
      :scopes,
      :oauth_client_id,
      :user_id,
      :last_refreshed,
      :credential_body_id
    ])
    |> validate_required([
      :body,
      :scopes,
      :oauth_client_id,
      :user_id,
      :last_refreshed
    ])
    |> assoc_constraint(:oauth_client)
    |> assoc_constraint(:user)
    |> assoc_constraint(:credential_body)
    |> validate_change(:body, &validate_oauth_body/2)
  end

  defp validate_oauth_body(:body, body) do
    case OauthValidation.validate_token_data(body) do
      {:ok, _} ->
        []

      {:error, %OauthValidation.Error{} = error} ->
        [{:body, {error.message, [type: error.type, details: error.details]}}]
    end
  end

  @doc """
  Creates a changeset for updating token data.

  Preserves the `refresh_token` from the existing token if the provider doesn't return a new one.
  This is common with some OAuth providers that only return `refresh_token` on initial authorization.

  By default, this function updates the `last_refreshed` timestamp to the current UTC time.
  If the update is not the result of an actual token refresh (e.g., only scopes changed),
  you can pass the option `refreshed: false` to skip updating the timestamp.

  ## Parameters

    - `oauth_token` - The existing `OauthToken` struct.
    - `new_token` - A map containing new token data from the OAuth provider.
    - `opts` - (optional) A keyword list of options:
      - `:refreshed` - Whether this update corresponds to an actual token refresh (default: `true`).

  ## Examples

      iex> OauthToken.update_token_changeset(existing_token, %{
      ...>   "access_token" => "new_access_token",
      ...>   "expires_in" => 3600,
      ...>   "scope" => "read write admin"
      ...> })
      #Ecto.Changeset<...>

      iex> OauthToken.update_token_changeset(existing_token, new_token_map, refreshed: false)
      #Ecto.Changeset<...>

  """
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(oauth_token, attrs) do
    oauth_token
    |> cast(attrs, [:body, :scopes, :last_refreshed, :credential_body_id])
    |> validate_required([:body, :scopes, :last_refreshed])
    |> assoc_constraint(:credential_body)
  end

  @doc """
  Checks if the token is still fresh (not expired or about to expire).

  ## Parameters
  - `oauth_token` - The token to check
  - `buffer_minutes` - Minutes before expiry to consider stale (default: 5)

  ## Returns
  - `true` - Token is fresh and can be used
  - `false` - Token is stale (expired or expires within buffer period)

  ## Examples
      iex> OauthToken.still_fresh?(token)
      true

      iex> OauthToken.still_fresh?(token, 10)  # More conservative buffer
      false
  """
  @spec still_fresh?(t(), non_neg_integer()) :: boolean()
  def still_fresh?(
        %__MODULE__{} = oauth_token,
        buffer_minutes \\ @default_freshness_buffer_minutes
      ) do
    case calculate_expiry_time(oauth_token) do
      {:ok, expiry_time} ->
        buffer_time = DateTime.add(DateTime.utc_now(), buffer_minutes, :minute)
        DateTime.compare(expiry_time, buffer_time) == :gt

      :error ->
        false
    end
  end

  @spec calculate_expiry_time(t()) :: {:ok, DateTime.t()} | :error
  defp calculate_expiry_time(%__MODULE__{body: %{"expires_at" => expires_at}})
       when is_integer(expires_at) do
    {:ok, DateTime.from_unix!(expires_at)}
  end

  defp calculate_expiry_time(%__MODULE__{body: %{"expires_at" => expires_at}})
       when is_binary(expires_at) do
    case Integer.parse(expires_at) do
      {timestamp, ""} -> {:ok, DateTime.from_unix!(timestamp)}
      _ -> :error
    end
  end

  defp calculate_expiry_time(%__MODULE__{
         body: %{"expires_in" => expires_in},
         last_refreshed: last_refreshed
       })
       when is_integer(expires_in) and not is_nil(last_refreshed) do
    {:ok, DateTime.add(last_refreshed, expires_in, :second)}
  end

  defp calculate_expiry_time(%__MODULE__{
         body: %{"expires_in" => expires_in},
         last_refreshed: last_refreshed
       })
       when is_binary(expires_in) and not is_nil(last_refreshed) do
    case Integer.parse(expires_in) do
      {seconds, ""} -> {:ok, DateTime.add(last_refreshed, seconds, :second)}
      _ -> :error
    end
  end

  defp calculate_expiry_time(_), do: :error
end
