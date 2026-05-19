defmodule Lightning.AuthProviders.GoogleHandlerTest do
  use ExUnit.Case, async: false

  import Mox

  alias Lightning.AuthProviders.GoogleHandler
  alias Lightning.AuthProviders.Handler

  setup :verify_on_exit!

  setup do
    Mox.stub_with(Lightning.MockConfig, Lightning.Config.API)
    prev = Application.get_env(:lightning, :google_oauth)
    on_exit(fn -> Application.put_env(:lightning, :google_oauth, prev || []) end)
    :ok
  end

  test "build/0 returns :not_configured when credentials are missing" do
    Application.put_env(:lightning, :google_oauth, [])
    assert {:error, :not_configured} = GoogleHandler.build()
  end

  test "build/0 returns a configured handler when all keys are set" do
    Application.put_env(:lightning, :google_oauth,
      client_id: "id",
      client_secret: "secret",
      redirect_uri: "http://localhost/authenticate/google/callback"
    )

    assert {:ok, %Handler{name: "google", scope: "openid email profile"}} =
             GoogleHandler.build()
  end

  test "build/0 returns :not_configured when redirect_uri is missing" do
    Application.put_env(:lightning, :google_oauth,
      client_id: "id",
      client_secret: "secret"
    )

    assert {:error, :not_configured} = GoogleHandler.build()
  end
end
