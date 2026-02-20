defmodule Lightning.Channels.SinkAuth do
  @moduledoc """
  Maps a credential's schema type and body to an outbound HTTP Authorization header.

  ## Supported Schemas

  - `"http"` — Bearer token (`access_token`) or Basic auth (`username`+`password`)
  - `"dhis2"` — DHIS2 ApiToken (`pat`) or Basic auth (`username`+`password`)
  - `"oauth"` — Bearer token (`access_token`, with auto-refresh via `resolve_credential_body`)

  Schemas not in this list are rejected at config time. If an unsupported schema
  somehow reaches runtime, `build_auth_header/2` returns an error.
  """

  @supported_schemas ~w(http dhis2 oauth)

  @doc """
  Returns the list of credential schema types that can be used for sink auth.
  Used for config-time validation.
  """
  @spec supported_schemas() :: [String.t()]
  def supported_schemas, do: @supported_schemas

  @doc """
  Given a credential schema name and decrypted body map, returns the
  Authorization header value to set on the outbound request.

  Returns:
  - `{:ok, header_value}` — e.g., `"Bearer tok123"` or `"Basic dTpw"`
  - `{:error, :no_auth_fields}` — credential body missing required auth fields
  - `{:error, {:unsupported_schema, schema}}` — schema not in supported list
  """
  @spec build_auth_header(String.t(), map()) ::
          {:ok, String.t()}
          | {:error, :no_auth_fields | {:unsupported_schema, String.t()}}
  def build_auth_header("http", body) do
    cond do
      token = body["access_token"] ->
        {:ok, "Bearer #{token}"}

      body["username"] && body["password"] ->
        {:ok,
         "Basic #{Base.encode64("#{body["username"]}:#{body["password"]}")}"}

      true ->
        {:error, :no_auth_fields}
    end
  end

  def build_auth_header("dhis2", body) do
    cond do
      token = body["pat"] ->
        {:ok, "ApiToken #{token}"}

      body["username"] && body["password"] ->
        {:ok,
         "Basic #{Base.encode64("#{body["username"]}:#{body["password"]}")}"}

      true ->
        {:error, :no_auth_fields}
    end
  end

  def build_auth_header("oauth", body) do
    case body["access_token"] do
      nil -> {:error, :no_auth_fields}
      token -> {:ok, "Bearer #{token}"}
    end
  end

  def build_auth_header(schema, _body) do
    {:error, {:unsupported_schema, schema}}
  end
end
