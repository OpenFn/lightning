defmodule Lightning.AuthProviders.Salesforce do
  @moduledoc """
  Handles the specifics of the Salesforce OAuth authentication process.
  """
  @behaviour Lightning.AuthProviders.OAuthBehaviour

  alias Lightning.AuthProviders.Common
  require Logger

  def provider_name, do: "Salesforce"

  def scopes,
    do: %{
      optional:
        ~w(cdp_query_api pardot_api cdp_profile_api chatter_api cdp_ingest_api
    eclair_api wave_api api custom_permissions id lightning content openid full visualforce
    web chatbot_api user_registration_api forgot_password cdp_api sfap_api interaction_api),
      mandatory: ~w(refresh_token)
    }

  def scopes_doc_url,
    do:
      "https://help.salesforce.com/s/articleView?id=sf.remoteaccess_oauth_tokens_scopes.htm&type=5"

  def wellknown_url(sandbox) do
    key = if sandbox, do: :sandbox_wellknown_url, else: :prod_wellknown_url
    config = Common.get_config(:salesforce)
    config[key]
  end

  @impl true
  def build_client(wellknown_url, opts \\ []) do
    Common.build_client(:salesforce, wellknown_url, opts)
  end

  @impl true
  def authorize_url(client, state, scopes \\ [], opts \\ []) do
    predefined_scopes = ~w[refresh_token]
    combined_scopes = predefined_scopes ++ scopes
    Common.authorize_url(client, state, combined_scopes, opts)
  end

  @impl true
  def get_token(client, wellknown_url, params) do
    Common.get_token(client, params)
    |> Common.introspect(:salesforce, wellknown_url)
  end

  @impl true
  def refresh_token(client, token, wellknown_url) do
    Common.refresh_token(client, token)
    |> Common.introspect(:salesforce, wellknown_url)
  end

  @impl true
  def refresh_token(token, wellknown_url) do
    {:ok, %OAuth2.Client{} = client} = build_client(wellknown_url)
    refresh_token(client, token, wellknown_url)
  end

  @impl true
  def get_userinfo(client, token, wellknown_url) do
    Common.get_userinfo(client, token, wellknown_url)
  end
end
