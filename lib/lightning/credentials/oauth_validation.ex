defmodule Lightning.Credentials.OauthValidation do
  @moduledoc """
  Centralized OAuth token validation with structured error handling.

  This module provides comprehensive OAuth token validation used across
  OauthToken and Credential modules to ensure consistent validation logic.

  Validates OAuth 2.0 tokens according to RFC 6749 specifications with
  additional robustness for real-world OAuth provider variations.
  """

  alias Lightning.Credentials.OauthToken

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
            | :missing_scope
            | :missing_expiration
            | :invalid_access_token
            | :invalid_refresh_token
            | :invalid_expiration
            | :missing_token_type
            | :unsupported_token_type

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
  Validates OAuth token data according to OAuth 2.0 standards (RFC 6749).

  This function validates that all required OAuth fields are present and valid in the token data.
  Required fields: access_token, refresh_token, scope (or scopes), expires_in (or expires_at), token_type.

  ## Expiration Fields
  - `expires_in`: Duration in seconds until token expires (relative, preferred by OAuth 2.0)
  - `expires_at`: Absolute timestamp when token expires (Unix timestamp or ISO 8601)

  Only one expiration field is required. `expires_in` is preferred as it's less susceptible to
  clock skew issues between client and server.

  ## Parameters
    * `token_data` - The OAuth token data to validate

  ## Returns
    * `{:ok, token_data}` - Token data is valid
    * `{:error, %Error{}}` - Token data is invalid with structured error

  ## Examples

      iex> validate_token_data(%{
      ...>   "access_token" => "abc123",
      ...>   "refresh_token" => "def456",
      ...>   "token_type" => "Bearer",
      ...>   "expires_in" => 3600,  # 1 hour
      ...>   "scope" => "read write"
      ...> })
      {:ok, %{"access_token" => "abc123", ...}}

      iex> validate_token_data(%{
      ...>   "access_token" => "abc123",
      ...>   "refresh_token" => "def456",
      ...>   "token_type" => "Bearer",
      ...>   "expires_at" => 1672531200,  # Unix timestamp
      ...>   "scope" => "read write"
      ...> })
      {:ok, %{"access_token" => "abc123", ...}}

      iex> validate_token_data(%{"invalid" => "data"})
      {:error, %Error{type: :missing_access_token, message: "..."}}
  """
  @spec validate_token_data(any()) :: {:ok, map()} | {:error, Error.t()}
  def validate_token_data(token_data) do
    with normalized_data <- normalize_keys(token_data),
         :ok <- validate_token_format(token_data),
         :ok <- validate_access_token(normalized_data),
         :ok <- validate_refresh_token(normalized_data),
         :ok <- validate_token_type(normalized_data),
         :ok <- validate_scope_field(normalized_data),
         :ok <- validate_expiration(normalized_data) do
      {:ok, token_data}
    end
  end

  @doc """
  Validates that granted scopes match exactly what the user selected.

  Performs case-insensitive scope matching to handle OAuth provider variations.

  ## Parameters
    * `token_data` - The OAuth token response from the provider
    * `expected_scopes` - List of scopes the user selected

  ## Returns
    * `:ok` - All expected scopes were granted
    * `{:error, %Error{}}` - Some expected scopes missing or no scope data

  ## Examples

      iex> validate_scope_grant(%{"scope" => "read write admin"}, ["read", "write"])
      :ok

      iex> validate_scope_grant(%{"scope" => "read"}, ["read", "write"])
      {:error, %Error{type: :missing_scopes, details: %{missing_scopes: ["write"]}}}
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

  Handles both string and atom keys, and both "scope" and "scopes" fields.

  ## Parameters
    * `token_data` - Map containing OAuth token data

  ## Returns
    * `{:ok, [String.t()]}` - List of extracted scopes
    * `:error` - No valid scope data found

  ## Examples

      iex> extract_scopes(%{"scope" => "read write"})
      {:ok, ["read", "write"]}

      iex> extract_scopes(%{scopes: ["read", "write"]})
      {:ok, ["read", "write"]}

      iex> extract_scopes(%{"invalid" => "data"})
      :error
  """
  @spec extract_scopes(map()) :: {:ok, [String.t()]} | :error
  def extract_scopes(%{"scope" => scope}) when is_binary(scope) do
    {:ok, parse_scope_string(scope)}
  end

  def extract_scopes(%{scope: scope}) when is_binary(scope) do
    {:ok, parse_scope_string(scope)}
  end

  def extract_scopes(%{"scopes" => scopes}) when is_list(scopes) do
    {:ok, parse_scope_list(scopes)}
  end

  def extract_scopes(%{scopes: scopes}) when is_list(scopes) do
    {:ok, parse_scope_list(scopes)}
  end

  def extract_scopes(_), do: :error

  @doc """
  Normalizes OAuth scopes from various input formats into a consistent list.

  Handles multiple input formats:
  - nil -> []
  - OauthToken struct with body containing "scope" or "scopes"
  - String with delimited scopes
  - List of scopes (strings or atoms)
  - Single atom scope
  - Any other input -> []

  Returns lowercase, trimmed, non-empty scope strings with duplicates removed.

  ## Parameters
    * `input` - The input to normalize (various formats supported)
    * `delimiter` - String delimiter for parsing scope strings (default: " ")

  ## Returns
    * `[String.t()]` - List of normalized scope strings

  ## Examples

      iex> normalize_scopes("READ Write ADMIN")
      ["read", "write", "admin"]

      iex> normalize_scopes([:read, "WRITE", " admin "])
      ["read", "write", "admin"]

      iex> normalize_scopes(%OauthToken{body: %{"scope" => "read write"}})
      ["read", "write"]
  """
  @spec normalize_scopes(any(), String.t()) :: [String.t()]
  def normalize_scopes(input, delimiter \\ " ")

  def normalize_scopes(nil, _delimiter), do: []

  def normalize_scopes(%OauthToken{body: nil}, _delimiter), do: []

  def normalize_scopes(%OauthToken{body: body}, _delimiter)
      when not is_map(body),
      do: []

  def normalize_scopes(%OauthToken{body: body}, delimiter) when is_map(body) do
    cond do
      Map.has_key?(body, "scope") ->
        body |> Map.get("scope") |> normalize_scopes(delimiter)

      Map.has_key?(body, "scopes") ->
        body |> Map.get("scopes") |> normalize_scopes(delimiter)

      true ->
        []
    end
  end

  def normalize_scopes(scopes, _delimiter) when is_list(scopes) do
    scopes
    |> Enum.map(&convert_to_string/1)
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  def normalize_scopes(scopes, delimiter) when is_binary(scopes) do
    scopes
    |> String.downcase()
    |> String.split(delimiter)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  def normalize_scopes(scope, _delimiter) when is_atom(scope) do
    case convert_to_string(scope) do
      scope_str when is_binary(scope_str) and scope_str != "" ->
        [scope_str |> String.downcase() |> String.trim()]

      _ ->
        []
    end
  end

  def normalize_scopes(_input, _delimiter), do: []

  defp convert_to_string(value) when is_binary(value), do: value

  defp convert_to_string(value) when is_atom(value) and not is_nil(value) do
    try do
      Atom.to_string(value)
    rescue
      ArgumentError -> nil
    end
  end

  defp convert_to_string(_), do: nil

  defp validate_token_format(token_data) when not is_map(token_data) do
    {:error, Error.new(:invalid_token_format, "OAuth token must be a valid map")}
  end

  defp validate_token_format(_), do: :ok

  defp validate_access_token(%{"access_token" => token})
       when is_binary(token) and byte_size(token) > 0 do
    :ok
  end

  defp validate_access_token(%{"access_token" => token})
       when not is_binary(token) do
    {:error,
     Error.new(
       :invalid_access_token,
       "access_token must be a non-empty string, got: #{inspect(token)}"
     )}
  end

  defp validate_access_token(%{"access_token" => ""}) do
    {:error,
     Error.new(
       :invalid_access_token,
       "access_token cannot be empty"
     )}
  end

  defp validate_access_token(_) do
    {:error,
     Error.new(
       :missing_access_token,
       "Missing required OAuth field: access_token"
     )}
  end

  defp validate_refresh_token(%{"refresh_token" => token})
       when is_binary(token) and byte_size(token) > 0 do
    :ok
  end

  defp validate_refresh_token(%{"refresh_token" => token})
       when not is_binary(token) do
    {:error,
     Error.new(
       :invalid_refresh_token,
       "refresh_token must be a non-empty string, got: #{inspect(token)}"
     )}
  end

  defp validate_refresh_token(%{"refresh_token" => ""}) do
    {:error,
     Error.new(
       :invalid_refresh_token,
       "refresh_token cannot be empty"
     )}
  end

  defp validate_refresh_token(_) do
    {:error,
     Error.new(
       :missing_refresh_token,
       "Missing required OAuth field: refresh_token"
     )}
  end

  defp validate_token_type(%{"token_type" => "Bearer"}), do: :ok
  defp validate_token_type(%{"token_type" => "bearer"}), do: :ok

  defp validate_token_type(%{"token_type" => type}) when is_binary(type) do
    {:error,
     Error.new(
       :unsupported_token_type,
       "Unsupported token type: '#{type}'. Expected 'Bearer'"
     )}
  end

  defp validate_token_type(%{"token_type" => type}) do
    {:error,
     Error.new(
       :invalid_token_format,
       "token_type must be a string, got: #{inspect(type)}"
     )}
  end

  defp validate_token_type(_) do
    {:error,
     Error.new(
       :missing_token_type,
       "Missing required OAuth field: token_type"
     )}
  end

  defp validate_scope_field(%{"scope" => scope})
       when is_binary(scope) and scope != "",
       do: :ok

  defp validate_scope_field(%{"scopes" => scopes})
       when is_list(scopes) and length(scopes) > 0 do
    if Enum.all?(scopes, &is_binary/1) do
      :ok
    else
      {:error,
       Error.new(
         :invalid_oauth_response,
         "scopes array must contain only strings"
       )}
    end
  end

  defp validate_scope_field(%{"scope" => ""}) do
    {:error,
     Error.new(
       :missing_scope,
       "scope field cannot be empty"
     )}
  end

  defp validate_scope_field(%{"scopes" => []}) do
    {:error,
     Error.new(
       :missing_scope,
       "scopes array cannot be empty"
     )}
  end

  defp validate_scope_field(%{"scope" => scope}) when not is_binary(scope) do
    {:error,
     Error.new(
       :invalid_oauth_response,
       "scope must be a string, got: #{inspect(scope)}"
     )}
  end

  defp validate_scope_field(%{"scopes" => scopes}) when not is_list(scopes) do
    {:error,
     Error.new(
       :invalid_oauth_response,
       "scopes must be a list, got: #{inspect(scopes)}"
     )}
  end

  defp validate_scope_field(_) do
    {:error,
     Error.new(
       :missing_scope,
       "Missing required OAuth field: scope or scopes"
     )}
  end

  defp validate_expiration(%{"expires_in" => expires_in}) do
    validate_expires_in(expires_in)
  end

  defp validate_expiration(%{"expires_at" => expires_at}) do
    validate_expires_at(expires_at)
  end

  defp validate_expiration(_) do
    {:error,
     Error.new(
       :missing_expiration,
       "Missing expiration field: either expires_in or expires_at is required"
     )}
  end

  defp validate_expires_in(expires_in) when is_integer(expires_in) do
    cond do
      expires_in <= 0 ->
        {:error,
         Error.new(
           :invalid_expiration,
           "expires_in must be greater than 0 seconds, got: #{expires_in}"
         )}

      expires_in > 365 * 24 * 3600 ->
        {:error,
         Error.new(
           :invalid_expiration,
           "expires_in seems unreasonably long (#{expires_in} seconds = #{div(expires_in, 3600)} hours)"
         )}

      true ->
        :ok
    end
  end

  defp validate_expires_in(expires_in) when is_binary(expires_in) do
    case Integer.parse(expires_in) do
      {int_value, ""} ->
        validate_expires_in(int_value)

      _ ->
        {:error,
         Error.new(
           :invalid_expiration,
           "expires_in string must represent a valid positive integer, got: #{expires_in}"
         )}
    end
  end

  defp validate_expires_in(expires_in) do
    {:error,
     Error.new(
       :invalid_expiration,
       "expires_in must be a positive integer (seconds), got: #{inspect(expires_in)}"
     )}
  end

  defp validate_expires_at(expires_at) when is_integer(expires_at) do
    current_time = System.system_time(:second)
    min_valid_time = current_time - 86400
    max_valid_time = current_time + 365 * 24 * 3600

    cond do
      expires_at < min_valid_time ->
        {:error,
         Error.new(
           :invalid_expiration,
           "expires_at timestamp appears to be too far in the past (possible clock skew)"
         )}

      expires_at > max_valid_time ->
        {:error,
         Error.new(
           :invalid_expiration,
           "expires_at timestamp appears to be too far in the future"
         )}

      true ->
        :ok
    end
  end

  defp validate_expires_at(expires_at)
       when is_binary(expires_at) and byte_size(expires_at) > 0 do
    cond do
      Regex.match?(~r/^\d+$/, expires_at) ->
        case Integer.parse(expires_at) do
          {timestamp, ""} ->
            validate_expires_at(timestamp)

          _ ->
            {:error,
             Error.new(
               :invalid_expiration,
               "expires_at string must be a valid integer timestamp"
             )}
        end

      String.contains?(expires_at, ["T", "Z"]) or
          String.match?(expires_at, ~r/\d{4}-\d{2}-\d{2}/) ->
        :ok

      true ->
        {:error,
         Error.new(
           :invalid_expiration,
           "expires_at must be a Unix timestamp or ISO 8601 date string, got: #{expires_at}"
         )}
    end
  end

  defp validate_expires_at(expires_at) do
    {:error,
     Error.new(
       :invalid_expiration,
       "expires_at must be an integer timestamp or date string, got: #{inspect(expires_at)}"
     )}
  end

  defp extract_granted_scopes(token_data) do
    case extract_scopes(token_data) do
      {:ok, scopes} -> {:ok, scopes}
      :error -> {:error, :no_scope_data}
    end
  end

  defp check_scope_match(granted_scopes, expected_scopes) do
    granted_normalized = Enum.map(granted_scopes, &String.downcase/1)
    expected_normalized = Enum.map(expected_scopes, &String.downcase/1)

    missing_normalized = expected_normalized -- granted_normalized

    if Enum.empty?(missing_normalized) do
      :ok
    else
      missing_original =
        expected_scopes
        |> Enum.filter(fn scope ->
          String.downcase(scope) in missing_normalized
        end)

      scope_list = Enum.join(missing_original, ", ")

      message =
        "Missing required scopes: #{scope_list}. Please reauthorize and grant all selected permissions."

      details = %{
        expected_scopes: expected_scopes,
        granted_scopes: granted_scopes,
        missing_scopes: missing_original
      }

      {:error, Error.new(:missing_scopes, message, details)}
    end
  end

  defp parse_scope_string(scope_string) do
    scope_string
    |> String.split(~r/\s+/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_scope_list(scopes) when is_list(scopes) do
    scopes
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
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
