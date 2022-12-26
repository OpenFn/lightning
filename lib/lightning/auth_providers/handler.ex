defmodule Lightning.AuthProviders.Handler do
  @moduledoc """
  Module which wraps Oauth configuration and a WellKnown document
  into a convenient struct that can be used to authenticate users against
  any OIDC compliant provider.
  """

  alias Lightning.AuthProviders.WellKnown

  @type t :: %__MODULE__{
          name: String.t(),
          client: OAuth2.Client.t(),
          wellknown: WellKnown.t()
        }

  @type opts :: [
          client_id: String.t(),
          client_secret: String.t(),
          redirect_uri: String.t(),
          wellknown: WellKnown.t()
        ]

  defstruct [:name, :client, :wellknown]

  @doc """
  Create a new Provider struct, expects a name and opts:

  - `:client_id` - The providers issued id
  - `:client_secret` - Secret for the client
  - `:redirect_uri` - The URI for redirecting after authentication,
    usually the callback url in the router.
  - `:wellknown` - A AuthProviders.WellKnown struct with the providers
    `.well-known/openid-configuration`.
  """
  @spec new(name :: String.t(), opts :: opts()) ::
          {:ok, __MODULE__.t()} | {:error, term()}
  def new(name, opts) do
    case validate_opts(opts) do
      {:error, error} ->
        {:error, error}

      :ok ->
        wellknown = opts[:wellknown]

        client =
          OAuth2.Client.new(
            strategy: OAuth2.Strategy.AuthCode,
            client_id: opts[:client_id],
            client_secret: opts[:client_secret],
            authorize_url: wellknown.authorization_endpoint,
            token_url: wellknown.token_endpoint,
            redirect_uri: opts[:redirect_uri]
          )
          |> OAuth2.Client.put_serializer("application/json", Jason)

        {:ok,
         struct!(__MODULE__, name: name, client: client, wellknown: wellknown)}
    end
  end

  @doc """
  Returns a Handler from a given AuthConfig
  """
  @spec from_model(model :: nil | Lightning.AuthProviders.AuthConfig.t()) ::
          {:ok, __MODULE__.t()} | {:error, term()}

  def from_model(nil), do: {:error, :not_found}

  def from_model(model) do
    opts =
      model
      |> Map.from_struct()
      |> Keyword.new(fn
        {:discovery_url, v} -> {:wellknown, WellKnown.fetch!(v)}
        {k, v} -> {k, v}
      end)

    new(model.name, opts)
  end

  @spec authorize_url(handler :: __MODULE__.t()) :: String.t()
  def authorize_url(handler) do
    OAuth2.Client.authorize_url!(handler.client, scope: "openid email profile")
  end

  @spec get_token(handler :: __MODULE__.t(), code :: String.t()) ::
          {:ok, OAuth2.AccessToken.t()} | {:error, map()}
  def get_token(handler, code) when is_binary(code) do
    case OAuth2.Client.get_token(handler.client,
           code: code,
           scope: "openid email profile"
         ) do
      {:ok, client} -> {:ok, client.token}
      {:error, %OAuth2.Response{body: body}} -> {:error, body}
    end
  end

  @spec get_userinfo(handler :: __MODULE__.t(), token :: OAuth2.AccessToken.t()) ::
          map()
  def get_userinfo(handler, token) do
    OAuth2.Client.get!(
      %{handler.client | token: token},
      handler.wellknown.userinfo_endpoint
    ).body
  end

  defp validate_opts(opts) do
    with nil <-
           [:client_id, :client_secret, :redirect_uri, :wellknown]
           |> expect_key(opts, fn key ->
             "Provider expects a '#{key}' key."
           end),
         nil <-
           [:authorization_endpoint, :token_endpoint]
           |> expect_key(opts[:wellknown] |> Map.from_struct(), fn key ->
             "Provider expects a WellKnown struct with a '#{key}' key."
           end) do
      :ok
    else
      e -> e
    end
  end

  defp expect_key(keys, opts, err_func) do
    keys
    |> Enum.map(fn key ->
      if get_in(opts, [key]), do: :ok, else: {:error, err_func.(key)}
    end)
    |> Enum.find(&match?({:error, _}, &1))
  end
end
