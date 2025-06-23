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

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          body: map(),
          scopes: [String.t()],
          oauth_client_id: Ecto.UUID.t() | nil,
          oauth_client: OauthClient.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          user: User.t() | nil,
          credential: Credential.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "oauth_tokens" do
    field :body, Lightning.Encrypted.Map, redact: true
    field :scopes, {:array, :string}
    field :last_refreshed, :utc_datetime

    field :oauth_error_type, :string, virtual: true
    field :oauth_error_details, :map, virtual: true

    belongs_to :oauth_client, OauthClient
    belongs_to :user, User

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
  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs), do: changeset(%__MODULE__{}, attrs)

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(oauth_token, attrs) do
    oauth_token
    |> cast(attrs, [:body, :scopes, :oauth_client_id, :user_id, :last_refreshed])
    |> validate_required([:body, :oauth_client_id, :user_id])
    |> assoc_constraint(:oauth_client)
    |> assoc_constraint(:user)
    |> validate_oauth_body()
    |> maybe_extract_scopes()
    |> validate_scopes_consistency()
  end

  @doc """
  Extracts scopes from OAuth token data.
  Delegates to OauthValidation.extract_scopes/1 for consistent scope handling.
  """
  defdelegate extract_scopes(token_data), to: OauthValidation

  @doc """
  Creates a changeset for updating token data.

  Preserves the refresh_token from the existing token if the provider doesn't return a new one.
  This is common with some OAuth providers that only return refresh_token on initial authorization.

  ## Parameters
  - `oauth_token` - The existing OauthToken struct
  - `new_token` - Map containing new token data from the OAuth provider

  ## Examples

      iex> OauthToken.update_token_changeset(existing_token, %{
      ...>   "access_token" => "new_access_token",
      ...>   "expires_in" => 3600,
      ...>   "scope" => "read write admin"
      ...> })
      #Ecto.Changeset<...>
  """
  @spec update_token_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_token_changeset(oauth_token, new_token) do
    scopes = extract_and_normalize_scopes(new_token)

    body = ensure_refresh_token(oauth_token, new_token)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    oauth_token
    |> cast(%{body: body, scopes: scopes, last_refreshed: now}, [
      :body,
      :scopes,
      :last_refreshed
    ])
    |> validate_required([:body, :scopes])
    |> validate_oauth_body()
  end

  @doc """
  Checks if the OAuth token has expired based on its expiration data.

  ## Examples

      iex> OauthToken.expired?(%OauthToken{body: %{"expires_at" => past_timestamp}})
      true

      iex> OauthToken.expired?(%OauthToken{body: %{"expires_in" => 3600}, updated_at: recent_time})
      false
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{body: body, updated_at: updated_at}) do
    case body do
      %{"expires_at" => expires_at} when is_integer(expires_at) ->
        expires_at < System.system_time(:second)

      %{"expires_at" => expires_at} when is_binary(expires_at) ->
        case Integer.parse(expires_at) do
          {timestamp, ""} -> timestamp < System.system_time(:second)
          _ -> false
        end

      %{"expires_in" => expires_in}
      when is_integer(expires_in) and not is_nil(updated_at) ->
        expiry_time = DateTime.add(updated_at, expires_in, :second)
        DateTime.compare(expiry_time, DateTime.utc_now()) == :lt

      %{"expires_in" => expires_in}
      when is_binary(expires_in) and not is_nil(updated_at) ->
        case Integer.parse(expires_in) do
          {seconds, ""} ->
            expiry_time = DateTime.add(updated_at, seconds, :second)
            DateTime.compare(expiry_time, DateTime.utc_now()) == :lt

          _ ->
            false
        end

      _ ->
        false
    end
  end

  @doc """
  Checks if the OAuth token is valid (not expired and passes OAuth validation).

  ## Examples

      iex> OauthToken.valid?(%OauthToken{body: valid_body})
      true
  """
  @spec valid?(t()) :: boolean()
  def valid?(oauth_token) do
    not expired?(oauth_token) and oauth_valid?(oauth_token)
  end

  @doc """
  Checks if the OAuth token needs to be refreshed based on age and expiration.

  ## Parameters
  - `oauth_token` - The OauthToken to check
  - `max_age_hours` - Maximum age in hours before refresh is recommended (default: 1)

  ## Examples

      iex> OauthToken.needs_refresh?(%OauthToken{last_refreshed: old_time})
      true

      iex> OauthToken.needs_refresh?(%OauthToken{last_refreshed: recent_time})
      false
  """
  @spec needs_refresh?(t(), integer()) :: boolean()
  def needs_refresh?(oauth_token, max_age_hours \\ 1)

  def needs_refresh?(%__MODULE__{last_refreshed: nil}, _), do: true

  def needs_refresh?(%__MODULE__{last_refreshed: last_refreshed}, max_age_hours) do
    age_hours = DateTime.diff(DateTime.utc_now(), last_refreshed, :hour)
    age_hours >= max_age_hours
  end

  @doc """
  Checks if the OAuth token is stale (needs refresh) or expired.

  ## Examples

      iex> OauthToken.stale_or_expired?(%OauthToken{last_refreshed: old_time})
      true
  """
  @spec stale_or_expired?(t(), integer()) :: boolean()
  def stale_or_expired?(oauth_token, max_age_hours \\ 1) do
    expired?(oauth_token) or needs_refresh?(oauth_token, max_age_hours)
  end

  @doc """
  Returns the age of the token in hours since last refresh.

  ## Examples

      iex> OauthToken.age_in_hours(%OauthToken{last_refreshed: two_hours_ago})
      2
  """
  @spec age_in_hours(t()) :: integer() | nil
  def age_in_hours(%__MODULE__{last_refreshed: nil}), do: nil

  def age_in_hours(%__MODULE__{last_refreshed: last_refreshed}) do
    DateTime.diff(DateTime.utc_now(), last_refreshed, :hour)
  end

  defp validate_oauth_body(changeset) do
    case fetch_field(changeset, :body) do
      {_, nil} ->
        add_error(changeset, :body, "OAuth token body is required")

      {_, body} when is_map(body) ->
        case OauthValidation.validate_token_data(body) do
          {:ok, _} ->
            changeset

          {:error, %OauthValidation.Error{} = error} ->
            add_oauth_error(changeset, error)
        end

      {_, _} ->
        add_error(changeset, :body, "OAuth token body must be a map")
    end
  end

  defp maybe_extract_scopes(changeset) do
    case fetch_field(changeset, :scopes) do
      {_, nil} ->
        case fetch_field(changeset, :body) do
          {_, body} when is_map(body) ->
            scopes = extract_and_normalize_scopes(body)
            put_change(changeset, :scopes, scopes)

          _ ->
            changeset
        end

      {_, scopes} when is_list(scopes) ->
        normalized_scopes = OauthValidation.normalize_scopes(scopes)
        put_change(changeset, :scopes, normalized_scopes)

      _ ->
        changeset
    end
  end

  defp validate_scopes_consistency(changeset) do
    with {_, body} when is_map(body) <- fetch_field(changeset, :body),
         {_, scopes} when is_list(scopes) <- fetch_field(changeset, :scopes) do
      case OauthValidation.extract_scopes(body) do
        {:ok, body_scopes} ->
          normalized_body_scopes = OauthValidation.normalize_scopes(body_scopes)
          normalized_field_scopes = OauthValidation.normalize_scopes(scopes)

          if normalized_body_scopes == normalized_field_scopes do
            changeset
          else
            add_error(
              changeset,
              :scopes,
              "scopes field does not match scopes in token body"
            )
          end

        :error ->
          changeset
      end
    else
      _ -> changeset
    end
  end

  defp extract_and_normalize_scopes(token_data) do
    case OauthValidation.extract_scopes(token_data) do
      {:ok, scopes} -> OauthValidation.normalize_scopes(scopes)
      :error -> []
    end
  end

  defp ensure_refresh_token(
         %__MODULE__{body: %{"refresh_token" => refresh_token}},
         new_token
       )
       when is_map(new_token) do
    case Map.get(new_token, "refresh_token") do
      nil -> Map.put(new_token, "refresh_token", refresh_token)
      _ -> new_token
    end
  end

  defp ensure_refresh_token(_, new_token), do: new_token

  defp oauth_valid?(%__MODULE__{body: body}) when is_map(body) do
    case OauthValidation.validate_token_data(body) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp oauth_valid?(_), do: false

  defp add_oauth_error(
         changeset,
         %OauthValidation.Error{} = error
       ) do
    changeset
    |> add_error(:body, error.message)
    |> put_change(:oauth_error_type, error.type)
    |> put_change(:oauth_error_details, error.details)
  end
end
