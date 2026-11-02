defmodule LightningWeb.API.InstanceControllerTest do
  # Sign-in providers live in a cache every test shares.
  use LightningWeb.ConnCase, async: false

  import LightningWeb.API.SessionHelpers
  import Lightning.Factories

  alias Lightning.AuthProviders
  alias Lightning.Config.API, as: ConfigAPI

  setup do
    Mox.stub(Lightning.MockConfig, :check_flag?, fn
      :allow_first_setup -> false
      :allow_signup -> true
      flag -> ConfigAPI.check_flag?(flag)
    end)

    Mox.stub(Lightning.MockConfig, :instance_admin_email, fn ->
      "support@example.org"
    end)

    Mox.stub(Lightning.MockConfig, :purge_deleted_after_days, fn -> 7 end)

    Mox.stub(Lightning.MockConfig, :apollo, fn
      :endpoint -> "http://apollo.example.org"
      :ai_assistant_api_key -> "a-key"
      key -> ConfigAPI.apollo(key)
    end)

    Mox.stub(LightningMock, :release, fn ->
      %{
        label: "v2.19.1",
        commit: "a1b2c3d",
        image_tag: "2.19.1",
        branch: nil,
        vsn: "2.19.1"
      }
    end)

    :ok
  end

  defp create_handler(name) do
    {:ok, handler} =
      AuthProviders.Handler.new(name,
        wellknown: %AuthProviders.WellKnown{
          authorization_endpoint: "https://sso.example.org/authorize",
          token_endpoint: "https://sso.example.org/token",
          userinfo_endpoint: "https://sso.example.org/userinfo"
        },
        client_id: "id",
        client_secret: "secret",
        redirect_uri: "http://localhost/callback_url"
      )

    {:ok, _} = AuthProviders.create_handler(handler)
    on_exit(fn -> AuthProviders.remove_handler(handler) end)
  end

  defp read_instance(conn),
    do:
      conn |> get(~p"/api/instance") |> json_response(200) |> Map.fetch!("data")

  test "reads the instance before anyone signs in, without its support address" do
    create_handler("keycloak")
    url = LightningWeb.Endpoint.url()

    redirect_uri = URI.encode_www_form(url <> "/oauth/github/callback")

    assert read_instance(build_conn()) == %{
             "needs_setup" => false,
             "allow_signup" => true,
             "url" => url,
             "release" => %{
               "label" => "v2.19.1",
               "commit" => "a1b2c3d",
               "image_tag" => "2.19.1",
               "branch" => nil
             },
             "admin_email" => nil,
             "purge_deleted_after_days" => 7,
             "sign_in_providers" => [
               %{
                 "name" => "keycloak",
                 "kind" => "external",
                 "start_url" => url <> "/authenticate/keycloak"
               }
             ],
             "ai_assistant" => true,
             "github_sync" => true,
             "github_connect_url" =>
               "https://github.com/login/oauth/authorize?client_id=abcd1234&redirect_uri=" <>
                 redirect_uri
           }
  end

  test "gives the support address only to a signed-in session token from Lightning's own page" do
    user = insert(:user)

    assert read_instance(session_conn(build_conn(), user))["admin_email"] ==
             "support@example.org"

    for conn <- [
          session_conn(build_conn(), user, origin: :cross),
          session_conn(build_conn(), insert(:user, mfa_enabled: true),
            mfa_pending: true
          ),
          put_req_header(
            build_conn(),
            "authorization",
            "Bearer " <> Lightning.Accounts.generate_api_token(user)
          )
        ] do
      assert read_instance(conn)["admin_email"] == nil
    end
  end

  @tag create_initial_user: false
  test "needs setup only while first setup is allowed and there is no superuser" do
    for {first_setup?, superuser?, needs_setup} <- [
          {true, false, true},
          {true, true, false},
          {false, false, false}
        ] do
      Mox.stub(Lightning.MockConfig, :check_flag?, fn
        :allow_first_setup -> first_setup?
        flag -> ConfigAPI.check_flag?(flag)
      end)

      if superuser?, do: insert(:user, role: :superuser)

      assert read_instance(build_conn())["needs_setup"] == needs_setup
    end
  end

  test "says when GitHub sync and the AI assistant aren't set up" do
    github_app = Application.get_env(:lightning, :github_app)
    Application.put_env(:lightning, :github_app, [])
    on_exit(fn -> Application.put_env(:lightning, :github_app, github_app) end)

    Mox.stub(Lightning.MockConfig, :apollo, fn _key -> nil end)

    assert %{
             "github_sync" => false,
             "github_connect_url" => nil,
             "ai_assistant" => false
           } = read_instance(build_conn())
  end
end
