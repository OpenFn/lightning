defmodule Lightning.AuthProviders.GithubHandlerTest do
  use ExUnit.Case, async: false

  import Mox

  alias Lightning.AuthProviders.GithubHandler
  alias Lightning.AuthProviders.Handler

  setup :verify_on_exit!

  setup do
    Mox.stub_with(Lightning.MockConfig, Lightning.Config.API)
    prev = Application.get_env(:lightning, :github_oauth)
    on_exit(fn -> Application.put_env(:lightning, :github_oauth, prev || []) end)
    :ok
  end

  test "build/0 returns :not_configured when credentials are missing" do
    Application.put_env(:lightning, :github_oauth, [])
    assert {:error, :not_configured} = GithubHandler.build()
  end

  test "build/0 returns a configured handler with a user emails endpoint" do
    Application.put_env(:lightning, :github_oauth,
      client_id: "id",
      client_secret: "secret",
      redirect_uri: "http://localhost/authenticate/github/callback"
    )

    assert {:ok, %Handler{name: "github", wellknown: wellknown}} =
             GithubHandler.build()

    # GitHub's /user endpoint does not reliably return a verified email, so the
    # handler must point at /user/emails for fallback resolution.
    assert wellknown.user_emails_endpoint == "https://api.github.com/user/emails"
  end

  test "build/0 returns :not_configured when redirect_uri is missing" do
    Application.put_env(:lightning, :github_oauth,
      client_id: "id",
      client_secret: "secret"
    )

    assert {:error, :not_configured} = GithubHandler.build()
  end
end
