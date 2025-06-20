defmodule Lightning.Credentials.OauthValidation do
  @moduledoc """
  Centralized OAuth token validation with structured error handling.

  This module provides comprehensive OAuth token validation used across
  OauthToken and Credential modules to ensure consistent validation logic.
  """

  import Ecto.Query

  alias Lightning.Credentials.OauthClient
  alias Lightning.Credentials.OauthToken
  alias Lightning.Repo

  defmodule Error do
    @moduledoc """
    Represents OAuth-related errors with structured error information.

    This module provides a standardized way to handle and categorize OAuth errors
    that can occur during authentication flows, token validation, and scope verification.
    Each error includes a type for programmatic handling, a human-readable message,
    and optional details for additional context.

    ## Examples

        iex> Error.new(:missing_scopes, "Required scopes not granted")
        %Error{type: :missing_scopes, message: "Required scopes not granted", details: nil}

        iex> Error.new(:missing_refresh_token, "No refresh token", %{existing_token_available: true})
        %Error{type: :missing_refresh_token, message: "No refresh token", details: %{existing_token_available: true}}
    """

    @type error_type ::
            :missing_scopes
            | :missing_refresh_token
            | :invalid_token_format
            | :missing_token_data
            | :invalid_oauth_response
            | :missing_access_token
            | :missing_expiration
            | :generic_oauth_error

    @type t :: %__MODULE__{
            type: error_type(),
            message: String.t(),
            details: map() | nil
          }

    defstruct [:type, :message, :details]

    @spec new(error_type(), String.t(), map() | nil) :: t()
    def new(type, message, details \\ nil) do
      %__MODULE__{type: type, message: message, details: details}
    end
  end

  @doc """
  Validates OAuth token data according to OAuth standards.

  ## Parameters
    * `token_data` - The OAuth token data to validate
    * `user_id` - User ID associated with the token
    * `oauth_client_id` - OAuth client ID
    * `scopes` - List of scopes for the token

  ## Returns
    * `{:ok, token_data}` - Token data is valid
    * `{:error, %Error{}}` - Token data is invalid with structured error

  ## Refresh Token Logic
  A refresh token is only required for completely new OAuth connections.
  It's NOT required if:
  - An existing token already exists for this user/client/scope combination
  - The new token data includes a refresh token
  """
  @spec validate_token_data(map(), String.t(), String.t(), [String.t()]) ::
          {:ok, map()} | {:error, Error.t()}
  def validate_token_data(token_data, user_id, oauth_client_id, scopes) do
    with :ok <- validate_token_format(token_data),
         :ok <- validate_scopes_present(scopes),
         normalized_data <- normalize_keys(token_data),
         :ok <- validate_access_token(normalized_data),
         :ok <-
           validate_refresh_token_requirements(
             normalized_data,
             user_id,
             oauth_client_id,
             scopes
           ),
         :ok <- validate_expiration_fields(normalized_data) do
      {:ok, token_data}
    end
  end

  @doc """
  Validates that granted scopes match exactly what the user selected.

  ## Parameters
    * `token_data` - The OAuth token response from the provider
    * `expected_scopes` - List of scopes the user selected

  ## Returns
    * `:ok` - All expected scopes were granted
    * `{:error, %Error{}}` - Some expected scopes missing or no scope data
  """
  @spec validate_scope_grant(map(), [String.t()]) :: :ok | {:error, Error.t()}
  def validate_scope_grant(token_data, expected_scopes) do
    case extract_granted_scopes(token_data) do
      {:ok, granted_scopes} ->
        check_scope_match(granted_scopes, expected_scopes)

      {:error, :no_scope_data} ->
        {:error,
         Error.new(
           :invalid_oauth_response,
           "OAuth token missing scope information"
         )}
    end
  end

  @doc """
  Extracts scopes from OAuth token data in various formats.
  """
  @spec extract_scopes(map()) :: {:ok, [String.t()]} | :error
  def extract_scopes(%{"scope" => scope}) when is_binary(scope) do
    {:ok, String.split(scope, " ")}
  end

  def extract_scopes(%{scope: scope}) when is_binary(scope) do
    {:ok, String.split(scope, " ")}
  end

  def extract_scopes(%{"scopes" => scopes}) when is_list(scopes) do
    {:ok, scopes}
  end

  def extract_scopes(%{scopes: scopes}) when is_list(scopes) do
    {:ok, scopes}
  end

  def extract_scopes(_), do: :error

  @doc """
  Finds the most appropriate OAuth token for a user that matches the requested scopes.
  """
  @spec find_best_matching_token_for_scopes(String.t(), String.t() | nil, [
          String.t()
        ]) ::
          OauthToken.t() | nil
  def find_best_matching_token_for_scopes(_user_id, nil, _requested_scopes),
    do: nil

  def find_best_matching_token_for_scopes(
        user_id,
        oauth_client_id,
        requested_scopes
      )
      when is_list(requested_scopes) do
    with %OauthClient{mandatory_scopes: mandatory_scopes} <-
           Repo.get(OauthClient, oauth_client_id),
         available_tokens <-
           fetch_tokens_with_matching_client_credentials(
             user_id,
             oauth_client_id
           ) do
      select_best_matching_token(
        available_tokens,
        requested_scopes,
        mandatory_scopes
      )
    else
      _ -> nil
    end
  end

  @doc """
  Normalizes OAuth scopes from various input formats into a consistent list.
  """
  @spec normalize_scopes(any(), String.t()) :: [String.t()]
  def normalize_scopes(input, delimiter \\ " ")
  def normalize_scopes(nil, _delimiter), do: []

  def normalize_scopes(%OauthToken{body: body}, delimiter) do
    body |> Map.get("scope", "") |> normalize_scopes(delimiter)
  end

  def normalize_scopes(scopes, delimiter) when is_binary(scopes) do
    scopes
    |> String.downcase()
    |> String.split(delimiter)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Private validation functions
  defp validate_token_format(token_data) when not is_map(token_data) do
    {:error, Error.new(:invalid_token_format, "OAuth token must be a valid map")}
  end

  defp validate_token_format(_), do: :ok

  defp validate_scopes_present(nil) do
    {:error,
     Error.new(:invalid_oauth_response, "OAuth token missing scope information")}
  end

  defp validate_scopes_present(_), do: :ok

  defp validate_access_token(%{"access_token" => _}), do: :ok

  defp validate_access_token(_) do
    {:error,
     Error.new(
       :missing_access_token,
       "Missing required OAuth field: access_token"
     )}
  end

  defp validate_refresh_token_requirements(
         token_data,
         user_id,
         oauth_client_id,
         scopes
       ) do
    refresh_token_context = %{
      has_refresh_token: Map.has_key?(token_data, "refresh_token"),
      existing_token_exists: token_exists?(user_id, oauth_client_id, scopes)
    }

    if refresh_token_allowed?(refresh_token_context) do
      :ok
    else
      {:error,
       Error.new(
         :missing_refresh_token,
         "Missing refresh_token for new OAuth connection",
         %{existing_token_available: refresh_token_context.existing_token_exists}
       )}
    end
  end

  defp refresh_token_allowed?(%{existing_token_exists: true}), do: true
  defp refresh_token_allowed?(%{has_refresh_token: true}), do: true
  defp refresh_token_allowed?(_), do: false

  defp token_exists?(user_id, oauth_client_id, scopes)
       when is_nil(user_id) or is_nil(oauth_client_id) or is_nil(scopes) do
    false
  end

  defp token_exists?(user_id, oauth_client_id, scopes) do
    find_best_matching_token_for_scopes(user_id, oauth_client_id, scopes) != nil
  end

  defp validate_expiration_fields(token_data) do
    expires_fields = ["expires_in", "expires_at"]

    if Enum.any?(expires_fields, &Map.has_key?(token_data, &1)) do
      :ok
    else
      {:error,
       Error.new(
         :missing_expiration,
         "Missing expiration field: either expires_in or expires_at is required"
       )}
    end
  end

  defp extract_granted_scopes(%{"scope" => scope_string})
       when is_binary(scope_string) do
    scopes =
      scope_string
      |> String.split(" ")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    {:ok, scopes}
  end

  defp extract_granted_scopes(_), do: {:error, :no_scope_data}

  defp check_scope_match(granted_scopes, expected_scopes) do
    missing_scopes = expected_scopes -- granted_scopes

    if Enum.empty?(missing_scopes) do
      :ok
    else
      scope_list = Enum.join(missing_scopes, ", ")

      message =
        "Missing required scopes: #{scope_list}. Please reauthorize and grant all selected permissions."

      details = %{
        expected_scopes: expected_scopes,
        granted_scopes: granted_scopes,
        missing_scopes: missing_scopes
      }

      {:error, Error.new(:missing_scopes, message, details)}
    end
  end

  # Token matching algorithm
  defp fetch_tokens_with_matching_client_credentials(user_id, oauth_client_id) do
    from(token in OauthToken,
      join: token_client in OauthClient,
      on: token.oauth_client_id == token_client.id,
      join: requested_client in OauthClient,
      on: requested_client.id == ^oauth_client_id,
      where:
        token.user_id == ^user_id and
          token_client.client_id == requested_client.client_id and
          token_client.client_secret == requested_client.client_secret
    )
    |> Repo.all()
  end

  defp select_best_matching_token(
         available_tokens,
         requested_scopes,
         mandatory_scopes_string
       ) do
    mandatory_scopes = normalize_scopes(mandatory_scopes_string, ",")
    requested_scope_set = MapSet.new(requested_scopes)
    mandatory_scope_set = MapSet.new(mandatory_scopes)

    effective_requested_scopes =
      MapSet.difference(requested_scope_set, mandatory_scope_set)

    if MapSet.size(effective_requested_scopes) == 0 do
      select_token_for_mandatory_only_request(
        available_tokens,
        mandatory_scope_set
      )
    else
      select_token_for_service_specific_request(
        available_tokens,
        effective_requested_scopes,
        mandatory_scope_set
      )
    end
  end

  defp select_token_for_mandatory_only_request(
         available_tokens,
         mandatory_scope_set
       ) do
    Enum.min_by(
      available_tokens,
      fn token ->
        token_scope_set = MapSet.new(token.scopes)

        effective_token_scopes =
          MapSet.difference(token_scope_set, mandatory_scope_set)

        {MapSet.size(effective_token_scopes),
         -DateTime.to_unix(token.updated_at)}
      end,
      fn -> nil end
    )
  end

  defp select_token_for_service_specific_request(
         available_tokens,
         effective_requested_scopes,
         mandatory_scope_set
       ) do
    available_tokens
    |> Enum.filter(
      &has_service_scope_overlap?(
        &1,
        effective_requested_scopes,
        mandatory_scope_set
      )
    )
    |> Enum.max_by(
      &calculate_token_score(
        &1,
        effective_requested_scopes,
        mandatory_scope_set
      ),
      fn -> nil end
    )
  end

  defp has_service_scope_overlap?(
         token,
         effective_requested_scopes,
         mandatory_scope_set
       ) do
    token_scope_set = MapSet.new(token.scopes)

    effective_token_scopes =
      MapSet.difference(token_scope_set, mandatory_scope_set)

    MapSet.intersection(effective_token_scopes, effective_requested_scopes)
    |> MapSet.size() > 0
  end

  defp calculate_token_score(
         token,
         effective_requested_scopes,
         mandatory_scope_set
       ) do
    token_scope_set = MapSet.new(token.scopes)

    effective_token_scopes =
      MapSet.difference(token_scope_set, mandatory_scope_set)

    matching_scope_count =
      MapSet.intersection(effective_token_scopes, effective_requested_scopes)
      |> MapSet.size()

    unrequested_scope_count =
      MapSet.difference(effective_token_scopes, effective_requested_scopes)
      |> MapSet.size()

    effective_requested_count = MapSet.size(effective_requested_scopes)

    exact_match? =
      matching_scope_count == effective_requested_count &&
        unrequested_scope_count == 0

    {
      if(exact_match?, do: 1, else: 0),
      matching_scope_count,
      -unrequested_scope_count,
      DateTime.to_unix(token.updated_at)
    }
  end

  defp normalize_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {k, v}, acc when is_map(v) ->
        Map.put(acc, to_string(k), normalize_keys(v))

      {k, v}, acc ->
        Map.put(acc, to_string(k), v)
    end)
  end

  defp normalize_keys(value), do: value
end
