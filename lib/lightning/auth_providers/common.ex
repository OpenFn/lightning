defmodule Lightning.AuthProviders.Common do
  @moduledoc """
  Provides common functionality for handling OAuth authentication across different providers.
  """

  alias Lightning.AuthProviders.WellKnown
  require Logger

  defmodule TokenBody do
    @moduledoc """
    Defines a schema for OAuth token information.
    """

    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :access_token, :string
      field :refresh_token, :string
      field :expires_at, :integer
      field :scope, :string
    end

    @doc """
    Creates a new TokenBody struct with the given attributes.
    """
    def new(attrs) do
      changeset(attrs) |> apply_changes()
    end

    @doc """
    Converts an OAuth2 token to a TokenBody struct.
    """
    def from_oauth2_token(token) do
      token_params = Map.from_struct(token)
      extra_params = token.other_params |> Enum.into(%{})

      token_params
      |> Map.merge(extra_params)
      |> new()
    end

    @doc false
    def changeset(attrs \\ %{}) do
      %__MODULE__{}
      |> cast(attrs, [:access_token, :refresh_token, :expires_at, :scope])
      |> validate_required([:access_token, :refresh_token])
    end
  end

  @doc """
  Requests an authentication token from the OAuth provider.
  """
  def get_token(client, params), do: OAuth2.Client.get_token(client, params)

  @doc """
  Refreshes the authentication token using the OAuth provider.
  """
  def refresh_token(client, token) do
    OAuth2.Client.refresh_token(%{client | token: token})
    |> handle_refresh_token_response()
  end

  @doc false
  defp handle_refresh_token_response({:ok, %{token: token}}), do: {:ok, token}

  defp handle_refresh_token_response(
         {:error, %OAuth2.Response{status_code: code, body: body}}
       ),
       do: {:error, %{code: code, body: body}}

  defp handle_refresh_token_response({:error, %{reason: reason}}),
    do: {:error, reason}

  @doc """
  Retrieves user information from the OAuth provider.
  """
  def get_userinfo(client, token, provider) do
    {:ok, wellknown} = get_wellknown(provider)
    OAuth2.Client.get(%{client | token: token}, wellknown.userinfo_endpoint)
  end

  @doc """
  Fetches the well-known configuration from the OAuth provider.
  """
  def get_wellknown(provider) do
    config = get_config(provider)
    wellknown_url = config[:wellknown_url]

    case Tesla.get(wellknown_url) do
      {:ok, %{status: status, body: body}} when status in 200..202 ->
        {:ok, Jason.decode!(body) |> WellKnown.new()}

      {:ok, %{status: status}} when status >= 500 ->
        {:error, "Received #{status} from #{wellknown_url}"}
    end
  end

  @doc """
  Fetches the well-known configuration from the OAuth provider and raises an error if not successful.
  """
  def get_wellknown!(provider) do
    get_wellknown(provider)
    |> case do
      {:ok, wellknown} ->
        wellknown

      {:error, reason} ->
        raise reason
    end
  end

  @doc """
  Builds a new OAuth client with the specified configuration, authorization URL, token URL, and options.
  """
  def build_client(config, authorize_url, token_url, opts \\ []) do
    if is_nil(config[:client_id]) or is_nil(config[:client_secret]) do
      Logger.error("""
      Please ensure the CLIENT_ID and CLIENT_SECRET ENV variables are set correctly.
      """)

      {:error, :invalid_config}
    else
      client =
        OAuth2.Client.new(strategy: OAuth2.Strategy.AuthCode)
        |> OAuth2.Client.put_serializer("application/json", Jason)
        |> Map.merge(%{
          authorize_url: authorize_url,
          token_url: token_url,
          client_id: config[:client_id],
          client_secret: config[:client_secret],
          redirect_uri: opts[:callback_url]
        })

      {:ok, client}
    end
  end

  @doc """
  Constructs the authorization URL with the given client, state, scopes, and options.
  """
  def authorize_url(client, state, scopes, opts \\ []) do
    scope = scopes |> Enum.join(" ")

    OAuth2.Client.authorize_url!(
      client,
      opts ++
        [
          scope: scope,
          state: state,
          access_type: "offline",
          prompt: "consent"
        ]
    )
  end

  @doc """
  Retrieves the configuration for a specified OAuth provider.
  """
  def get_config(provider) do
    Application.get_env(:lightning, :oauth_clients)
    |> Keyword.get(provider)
  end
end
