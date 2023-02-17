defmodule Lightning.AuthProviders.Google do
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
  def build_client(opts \\ []) do
    config = get_config()

    if is_nil(config[:client_id]) or is_nil(config[:client_secret]) do
      Logger.error("""
      Please ensure the following ENV variables are set correctly:

      - GOOGLE_CLIENT_ID
      - GOOGLE_CLIENT_SECRET
      """)

      raise "Required OAuth client configuration missing"
    end

    wellknown = get_wellknown()

    OAuth2.Client.new(
      strategy: OAuth2.Strategy.AuthCode,
      authorize_url: wellknown.authorization_endpoint,
      token_url: wellknown.token_endpoint,
      client_id: config[:client_id],
      client_secret: config[:client_secret],
      redirect_uri: opts[:callback_url]
    )
    |> OAuth2.Client.put_serializer("application/json", Jason)
  end

  def authorize_url(client, state) do
    scope = ~W[
      https://www.googleapis.com/auth/spreadsheets
      https://www.googleapis.com/auth/userinfo.profile
    ] |> Enum.join(" ")

    OAuth2.Client.authorize_url!(client,
      scope: scope,
      state: state,
      access_type: "offline"
    )
  end

  def get_token(client, params) do
    OAuth2.Client.get_token(client, params)
  end

  def get_userinfo(client, token) do
    wellknown = get_wellknown()

    OAuth2.Client.get(%{client | token: token}, wellknown.userinfo_endpoint)
  end

  def get_wellknown() do
    config = get_config()
    # TODO pass this onto a caching mechanism
    with {:ok, response} <- Tesla.get(config[:wellknown_url]),
         body <- Jason.decode!(response.body) do
      WellKnown.new(body)
    end
  end

  def get_config() do
    Application.get_env(:lightning, :oauth_clients, google: [])
    |> Keyword.get(:google)
  end
end
