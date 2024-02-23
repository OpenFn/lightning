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
      enabled:
        ~w(cdp_query_api pardot_api cdp_profile_api chatter_api cdp_ingest_api
    eclair_api wave_api api custom_permissions id lightning content openid full visualforce
    web chatbot_api user_registration_api forgot_password cdp_api sfap_api interaction_api),
      disabled: ~w(refresh_token)
    }

  def scopes_doc_url,
    do:
      "https://help.salesforce.com/s/articleView?id=sf.remoteaccess_oauth_tokens_scopes.htm&type=5"

  @impl true
  def build_client(opts \\ []) do
    Common.build_client(:salesforce, opts)
  end

  @impl true
  def authorize_url(client, state, scopes \\ [], opts \\ []) do
    predefined_scopes = ~w[refresh_token]
    combined_scopes = predefined_scopes ++ scopes
    Common.authorize_url(client, state, combined_scopes, opts)
  end

  @impl true
  def get_token(client, params) do
    Common.get_token(client, params) |> Common.introspect(:salesforce)
  end

  @impl true
  def refresh_token(client, token) do
    Common.refresh_token(client, token)
    |> Common.introspect(:salesforce)
  end

  @impl true
  def refresh_token(token) do
    {:ok, %OAuth2.Client{} = client} = build_client()
    refresh_token(client, token)
  end

  @impl true
  def get_userinfo(client, token) do
    Common.get_userinfo(client, token, :salesforce)
  end
end
