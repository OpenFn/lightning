defmodule LightningWeb.CredentialPageHelpers do
  @moduledoc """
  What the credentials page's test files share: opening `/credentials`,
  reading its props, sending its events, the values its forms send, and an
  OAuth sign-in answered through the provider's callback.

      import LightningWeb.CredentialPageHelpers
  """
  use LightningWeb, :verified_routes

  import ExUnit.Assertions
  import Lightning.Factories
  import LightningWeb.DesignSystemHelpers
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Lightning.Repo

  @endpoint LightningWeb.Endpoint
  @page "#credentials-index-page"

  @token %{
    "access_token" => "the-access-token",
    "refresh_token" => "the-refresh-token",
    "token_type" => "Bearer",
    "expires_in" => 3600,
    "scope" => "scope_1 scope_2"
  }

  def refused, do: "You are not authorized to perform this action"

  def token, do: @token

  def props(view), do: page_props(view, @page)

  def send_event(view, event, payload),
    do: push_page_event(view, @page, event, payload)

  def open(conn) do
    {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)
    view
  end

  def raw_values(attrs) do
    Map.merge(
      %{
        "formId" => "form-1",
        "name" => "My raw",
        "externalId" => "",
        "schema" => "raw",
        "oauthClientId" => nil,
        "projectIds" => [],
        "environments" => [
          %{
            "name" => "main",
            "previousName" => nil,
            "body" => ~s({"a": 1}),
            "signInId" => nil
          }
        ]
      },
      attrs
    )
  end

  def client_values(attrs) do
    Map.merge(
      %{
        "name" => "My client",
        "authorizationEndpoint" => "https://example.com/authorize",
        "tokenEndpoint" => "https://example.com/token",
        "revocationEndpoint" => "",
        "introspectionEndpoint" => "",
        "userinfoEndpoint" => "",
        "clientId" => "the-id",
        "clientSecret" => "the-secret",
        "mandatoryScopes" => ["read"],
        "optionalScopes" => [],
        "scopesDocUrl" => "",
        "global" => false,
        "projectIds" => []
      },
      attrs
    )
  end

  def oauth_values(client, sign_in_id, attrs \\ %{}) do
    raw_values(
      Map.merge(
        %{
          "schema" => "oauth",
          "oauthClientId" => client.id,
          "environments" => [
            %{
              "name" => "main",
              "previousName" => nil,
              "body" => "",
              "signInId" => sign_in_id
            }
          ]
        },
        attrs
      )
    )
  end

  def credential_with_body(user, attrs \\ %{}, body \\ %{"a" => "secret-a"}) do
    credential = insert(:credential, Map.merge(%{user: user}, attrs))
    insert(:credential_body, credential: credential, name: "main", body: body)
    credential
  end

  def bodies(credential) do
    credential
    |> Repo.preload(:credential_bodies, force: true)
    |> Map.fetch!(:credential_bodies)
    |> Map.new(&{&1.name, &1.body})
  end

  def stub_provider(client, token_reply \\ {200, @token}) do
    %{token_endpoint: token_url, userinfo_endpoint: userinfo_url} = client
    {status, body} = token_reply

    Mox.stub(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
      %{url: ^token_url} = env, _opts ->
        {:ok, %{env | status: status, body: body}}

      %{url: ^userinfo_url} = env, _opts ->
        {:ok,
         %{env | status: 200, body: %{"name" => "Ada", "email" => "ada@x.org"}}}
    end)
  end

  @doc "Starts a sign-in and answers it through the provider's callback."
  def sign_in(view, client, attrs \\ %{}, answer \\ %{code: "the-code"}) do
    send_event(
      view,
      "authorize_oauth",
      Map.merge(
        %{
          "formId" => "form-1",
          "signInId" => "s1",
          "credentialId" => nil,
          "oauthClientId" => client.id,
          "scopes" => ["scope_1", "scope_2"],
          "environment" => "main"
        },
        attrs
      )
    )

    assert_reply(view, %{authorizeUrl: url})
    assert String.starts_with?(url, client.authorization_endpoint)

    %{"state" => state} =
      url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    get(
      build_conn(),
      ~p"/authenticate/callback?#{Map.put(answer, :state, state)}"
    )

    render_async(view)
  end
end
