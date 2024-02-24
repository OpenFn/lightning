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
      field :instance_url, :string
      field :sandbox, :boolean, default: false
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
      Map.from_struct(token)
      |> Map.merge(token.other_params)
      |> Enum.into(%{}, fn {key, value} ->
        {key |> to_string(), value}
      end)
      |> new()
    end

    @doc false
    def changeset(attrs \\ %{}) do
      %__MODULE__{}
      |> cast(attrs, [
        :access_token,
        :refresh_token,
        :expires_at,
        :scope,
        :instance_url,
        :sandbox
      ])
      |> validate_required([:access_token, :refresh_token])
    end
  end

  @doc """
  Requests an authentication token from the OAuth provider.
  """
  def get_token(client, params),
    do: OAuth2.Client.get_token(client, params)

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
       do: {:error, %{status_code: code, body: body}}

  defp handle_refresh_token_response({:error, %{reason: reason}}),
    do: {:error, reason}

  @doc """
  Retrieves user information from the OAuth provider.
  """
  def get_userinfo(client, token, wellknown_url) do
    {:ok, wellknown} = get_wellknown(wellknown_url)

    OAuth2.Client.get(%{client | token: token}, wellknown.userinfo_endpoint)
  end

  @doc """
  Fetches the well-known configuration from the OAuth provider.
  """
  def get_wellknown(wellknown_url) do
    case Tesla.get(wellknown_url) do
      {:ok, %{status: status, body: body}} when status in 200..202 ->
        {:ok, Jason.decode!(body) |> WellKnown.new()}

      {:ok, %{status: status}} when status >= 500 ->
        {:error, "Received #{status} from #{wellknown_url}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches the well-known configuration from the OAuth provider and raises an error if not successful.
  """
  def get_wellknown!(wellknown_url) do
    get_wellknown(wellknown_url)
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
  def build_client(provider, wellknown_url, opts \\ []) do
    config = get_config(provider)

    if is_nil(config) or is_nil(config[:client_id]) or
         is_nil(config[:client_secret]) do
      Logger.error("""
      Please ensure the CLIENT_ID and CLIENT_SECRET ENV variables are set correctly.
      """)

      {:error, :invalid_config}
    else
      case get_wellknown(wellknown_url) do
        {:ok, wellknown} ->
          client =
            OAuth2.Client.new(strategy: OAuth2.Strategy.AuthCode)
            |> OAuth2.Client.put_serializer("application/json", Jason)
            |> Map.merge(%{
              authorize_url: wellknown.authorization_endpoint,
              token_url: wellknown.token_endpoint,
              client_id: config[:client_id],
              client_secret: config[:client_secret],
              redirect_uri: opts[:callback_url]
            })

          {:ok, client}

        {:error, :timeout} ->
          {:error, :timeout}
      end
    end
  end

  @doc """
  Constructs the authorization URL with the given client, state, scopes, and options.
  """
  def authorize_url(client, state, scopes, opts \\ []) do
    OAuth2.Client.authorize_url!(
      client,
      opts ++
        [
          scope: Enum.join(scopes, " "),
          state: state,
          access_type: "offline",
          prompt: "consent"
        ]
    )
  end

  def introspect(
        {:ok, %OAuth2.AccessToken{access_token: access_token} = token},
        provider,
        wellknown_url
      ) do
    {:ok, wellknown} = get_wellknown(wellknown_url)
    config = get_config(provider)

    Tesla.post(
      wellknown.introspection_endpoint,
      "token=#{access_token}&client_id=#{config[:client_id]}&client_secret=#{config[:client_secret]}&token_type_hint=access_token",
      headers: [
        {"Accept", "application/json"},
        {"Content-Type", "application/x-www-form-urlencoded"}
      ]
    )
    |> handle_introspection_result(token)
  end

  def introspect(result, _provider, _wellknow_url), do: result

  defp handle_introspection_result({:ok, %{status: status, body: body}}, token)
       when status in 200..202 do
    expires_at = Jason.decode!(body) |> Map.get("exp")
    updated_token = Map.update!(token, :expires_at, fn _ -> expires_at end)
    {:ok, updated_token}
  end

  defp handle_introspection_result({:ok, %{status: status}}, _token)
       when status not in 200..202,
       do: {:error, nil}

  @doc """
  Checks if a token is still valid or must be refreshed. If expires_at is nil,
  it will return `false`, forcing a refresh. If the token has already expired or
  will expire before the default buffer (in the next 5 minutes) we return
  `false`, forcing a refresh.
  """
  def still_fresh(token_body, threshold \\ 5, time_unit \\ :minute)

  def still_fresh(
        %{expires_at: nil},
        _threshold,
        _time_unit
      ),
      do: false

  def still_fresh(
        %{expires_at: expires_at},
        threshold,
        time_unit
      ) do
    current_time = DateTime.utc_now()
    expiration_time = DateTime.from_unix!(expires_at)
    time_remaining = DateTime.diff(expiration_time, current_time, time_unit)
    time_remaining >= threshold
  end

  @doc """
  Retrieves the configuration for a specified OAuth provider.
  """
  def get_config(provider) do
    Application.get_env(:lightning, :oauth_clients)
    |> Keyword.get(provider)
  end
end
