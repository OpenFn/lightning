defmodule Lightning.AuthProviders.Salesforce do
  alias Lightning.AuthProviders.WellKnown
  require Logger

  defmodule TokenBody do
    @moduledoc false

    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :access_token, :string
      field :refresh_token, :string
      field :expires_at, :integer
      field :scope, :string
    end

    def new(attrs) do
      changeset(attrs) |> apply_changes()
    end

    def from_oauth2_token(
          %OAuth2.AccessToken{
            other_params: %{"expires_at" => expires_at, "scope" => scope}
          } =
            token
        ) do
      Map.from_struct(token)
      |> Map.merge(%{expires_at: expires_at, scope: scope})
      |> new()
    end

    def from_oauth2_token(%OAuth2.AccessToken{} = token) do
      Map.from_struct(token) |> new()
    end

    @doc false
    def changeset(attrs \\ %{}) do
      %__MODULE__{}
      |> cast(attrs, [:access_token, :refresh_token, :expires_at, :scope])
      |> validate_required([:access_token, :refresh_token])
    end
  end

  @doc """
  Builds a new client
  """
  def build_client(_opts \\ []) do
    config = get_config()

    if is_nil(config[:consumer_key]) or is_nil(config[:consumer_key]) do
      Logger.error("""
      Please ensure the following ENV variables are set correctly:

      - SALESFORCE_CONSUMER_KEY
      - SALESFORCE_CONSUMER_SECRET
      """)

      {:error, :invalid_config}
    else
      client =
        OAuth2.Client.new(
          strategy: OAuth2.Strategy.AuthCode,
          authorize_url:
            "https://login.salesforce.com/services/oauth2/authorize",
          token_url: "https://login.salesforce.com/services/oauth2/token",
          client_id: config[:consumer_key],
          client_secret: config[:consumer_secret],
          redirect_uri: "http://localhost:4000/authenticate/callback"
        )
        |> OAuth2.Client.put_serializer("application/json", Jason)

      {:ok, client}
    end
  end

  # Refresh token is null, changeset error

  def authorize_url(client, state) do
    scope = ~W[
      full
      offline_access
    ] |> Enum.join(" ")

    OAuth2.Client.authorize_url!(client,
      scope: scope,
      state: state,
      access_type: "offline",
      prompt: "consent"
    )
  end

  def get_token(client, params) do
    OAuth2.Client.get_token(client, params)
  end

  # Use the the refresh token to get a new access token.
  @spec refresh_token(
          %{:token => any, optional(any) => any} | OAuth2.Client.t(),
          OAuth2.AccessToken.t() | %{refresh_token: binary()}
        ) ::
          {:error, binary | %{body: binary | list | map, code: integer}}
          | {:ok, nil | OAuth2.AccessToken.t()}
  def refresh_token(client, token) do
    OAuth2.Client.refresh_token(%{client | token: token})
    |> case do
      {:ok, %{token: token}} ->
        {:ok, token}

      {:error, %OAuth2.Response{status_code: code, body: body}} ->
        {:error, %{code: code, body: body}}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  def get_userinfo(client, token) do
    {:ok, wellknown} = get_wellknown()

    OAuth2.Client.get(%{client | token: token}, wellknown.userinfo_endpoint)
  end

  def get_wellknown do
    config = get_config()
    wellknown_url = config[:wellknown_url]
    # TODO pass this onto a caching mechanism
    case Tesla.get(wellknown_url) do
      {:ok, %{status: status, body: body}} when status in 200..202 ->
        {:ok, Jason.decode!(body) |> WellKnown.new()}

      {:ok, %{status: status}} when status >= 500 ->
        {:error, "Received #{status} from #{wellknown_url}"}
    end
  end

  def get_wellknown! do
    get_wellknown()
    |> case do
      {:ok, wellknown} ->
        wellknown

      {:error, reason} ->
        raise reason
    end
  end

  def get_config do
    Application.get_env(:lightning, :oauth_clients)
    |> Keyword.get(:salesforce)
  end
end
