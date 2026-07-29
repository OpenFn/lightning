defmodule Lightning.AuthProviders.WellKnown do
  @moduledoc """
  A datastructure to fetch and hold information about a given OIDC/OAuth provider
  """
  use HTTPoison.Base

  alias Lightning.AuthProviders.TLS

  @fields [
    :authorization_endpoint,
    :token_endpoint,
    :userinfo_endpoint,
    :introspection_endpoint,
    :jwks_uri,
    :issuer
  ]

  defstruct @fields

  @type t :: %__MODULE__{
          authorization_endpoint: String.t(),
          token_endpoint: String.t(),
          userinfo_endpoint: String.t(),
          introspection_endpoint: String.t(),
          jwks_uri: String.t() | nil,
          issuer: String.t() | nil
        }

  @spec fetch(discovery_url :: String.t()) ::
          {:ok, __MODULE__.t()} | {:error, reason :: term()}
  def fetch(discovery_url) do
    with :ok <- ensure_secure(discovery_url),
         {:ok, response} <- get(discovery_url),
         {:ok, decoded} <- Jason.decode(response.body) do
      {:ok, new(decoded)}
    end
  end

  @spec fetch!(discovery_url :: String.t()) ::
          __MODULE__.t()
  def fetch!(discovery_url) do
    with :ok <- ensure_secure(discovery_url),
         {:ok, response} <- get(discovery_url),
         {:ok, args} <- response.body |> Jason.decode() do
      new(args)
    end
  end

  # Refuse a plaintext discovery URL: the ssl opts below are inert over http, so
  # fetching there would leave `jwks_uri`/`issuer` unauthenticated and defeat the
  # JWKS TLS check downstream. Loopback is allowed for the test suite.
  defp ensure_secure(discovery_url) do
    if TLS.secure_url?(discovery_url),
      do: :ok,
      else: {:error, :insecure_discovery_url}
  end

  @spec new(json_body :: %{String.t() => term()}) :: __MODULE__.t()
  def new(%{} = json_body) do
    struct!(
      __MODULE__,
      @fields
      |> Enum.map(fn key ->
        {key, json_body[key |> to_string()]}
      end)
    )
  end

  # Verify the TLS chain on the discovery fetch too: it supplies `jwks_uri` and
  # `issuer`, so a MITM here would repoint verification at attacker keys and
  # defeat the JWKS TLS check downstream.
  def process_request_options(options) do
    Keyword.put_new(options, :ssl, TLS.verify_opts())
  end
end
