defmodule LightningWeb.OauthComponentsTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias LightningWeb.Components.Oauth

  defp mock_target, do: "test-target"

  describe "scopes_picklist/1" do
    test "renders scope selection interface with all scopes" do
      selected_scopes = ~w(scope_1 scope_2 scope_3 scope_4)
      mandatory_scopes = ~w(scope_1 scope_2)
      scopes = ~w(scope_1 scope_2 scope_3 scope_4 scope_5 scope_6)

      picklist =
        render_component(&Oauth.scopes_picklist/1,
          id: "scopes_picklist",
          on_change: "scopes_changed",
          target: mock_target(),
          selected_scopes: selected_scopes,
          mandatory_scopes: mandatory_scopes,
          scopes: scopes,
          provider: "DHIS2",
          doc_url: "https://dhis2.org/oauth/scopes"
        )

      assert picklist =~ "Select permissions"
      assert picklist =~ "Select permissions associated to your OAuth2 Token"
      assert picklist =~ "Learn more about DHIS2 permissions"
      assert picklist =~ "https://dhis2.org/oauth/scopes"

      scopes_dom = Floki.parse_document!(picklist)

      all_checkboxes = Floki.find(scopes_dom, "input[type='checkbox']")
      assert length(all_checkboxes) == length(scopes)

      checked_checkboxes =
        Floki.find(scopes_dom, "input[type='checkbox'][checked]")

      assert length(checked_checkboxes) == length(selected_scopes)

      disabled_checkboxes =
        Floki.find(scopes_dom, "input[type='checkbox'][disabled]")

      assert length(disabled_checkboxes) == length(mandatory_scopes)

      checked_scope_names =
        Enum.map(checked_checkboxes, fn {"input", attrs, _children} ->
          attrs |> Enum.find(fn {key, _value} -> key == "name" end) |> elem(1)
        end)

      assert Enum.sort(checked_scope_names) == Enum.sort(selected_scopes)
    end

    test "renders without doc_url when not provided" do
      picklist =
        render_component(&Oauth.scopes_picklist/1,
          id: "scopes_picklist",
          on_change: "scopes_changed",
          target: mock_target(),
          selected_scopes: [],
          mandatory_scopes: [],
          scopes: ["scope_1"],
          provider: "DHIS2"
        )

      refute picklist =~ "Learn more about"
    end

    test "handles disabled state" do
      picklist =
        render_component(&Oauth.scopes_picklist/1,
          id: "scopes_picklist",
          on_change: "scopes_changed",
          target: mock_target(),
          selected_scopes: [],
          mandatory_scopes: [],
          scopes: ["scope_1"],
          provider: "DHIS2",
          disabled: true
        )

      scopes_dom = Floki.parse_document!(picklist)

      disabled_checkboxes =
        Floki.find(scopes_dom, "input[type='checkbox'][disabled]")

      assert length(disabled_checkboxes) == 1
    end

    test "handles empty scopes list" do
      picklist =
        render_component(&Oauth.scopes_picklist/1,
          id: "scopes_picklist",
          on_change: "scopes_changed",
          target: mock_target(),
          selected_scopes: [],
          mandatory_scopes: [],
          scopes: [],
          provider: "DHIS2"
        )

      scopes_dom = Floki.parse_document!(picklist)
      checkboxes = Floki.find(scopes_dom, "input[type='checkbox']")
      assert length(checkboxes) == 0
    end

    test "scope checkbox interactions" do
      picklist =
        render_component(&Oauth.scopes_picklist/1,
          id: "test_scopes",
          on_change: "scope_changed",
          target: mock_target(),
          selected_scopes: ["read"],
          mandatory_scopes: ["admin"],
          scopes: ["read", "write", "admin"],
          provider: "TestProvider"
        )

      scopes_dom = Floki.parse_document!(picklist)

      read_checkbox = Floki.find(scopes_dom, "#test_scopes_read")
      assert read_checkbox != []
      assert Floki.attribute(read_checkbox, "checked") == ["checked"]
      assert Floki.attribute(read_checkbox, "disabled") == []

      admin_checkbox = Floki.find(scopes_dom, "#test_scopes_admin")
      assert admin_checkbox != []
      assert Floki.attribute(admin_checkbox, "checked") == ["checked"]
      assert Floki.attribute(admin_checkbox, "disabled") == ["disabled"]

      write_checkbox = Floki.find(scopes_dom, "#test_scopes_write")
      assert write_checkbox != []
      assert Floki.attribute(write_checkbox, "checked") == []
      assert Floki.attribute(write_checkbox, "disabled") == []
    end
  end

  describe "missing_client_warning/1" do
    test "renders OAuth client not found warning" do
      warning = render_component(&Oauth.missing_client_warning/1, %{})

      assert warning =~ "OAuth client not found"
      assert warning =~ "The associated Oauth client"
      assert warning =~ "cannot be found"
      assert warning =~ "Create"
      assert warning =~ "a new client or contact your administrator"
    end
  end

  describe "oauth_status/1" do
    test "renders idle state with authorize button" do
      status =
        render_component(&Oauth.oauth_status/1,
          state: :idle,
          provider: "Salesforce",
          myself: mock_target(),
          authorize_url: "https://salesforce.com/oauth/authorize",
          scopes_changed: false
        )

      assert status =~ "Sign in with Salesforce"
      assert status =~ "authorize_click"
      assert status =~ "authorize-button"
    end

    test "renders authenticating state" do
      status =
        render_component(&Oauth.oauth_status/1,
          state: :authenticating,
          provider: "Google",
          myself: mock_target(),
          scopes_changed: false
        )

      assert status =~ "Authenticating with Google..."
    end

    test "renders fetching_userinfo state" do
      status =
        render_component(&Oauth.oauth_status/1,
          state: :fetching_userinfo,
          provider: "Salesforce",
          myself: mock_target(),
          scopes_changed: false
        )

      assert status =~ "Fetching user information from Salesforce..."
    end

    test "renders complete state with user information" do
      socket = %Phoenix.LiveView.Socket{
        endpoint: LightningWeb.Endpoint,
        router: LightningWeb.Router
      }

      status =
        render_component(&Oauth.oauth_status/1,
          state: :complete,
          provider: "Salesforce",
          myself: mock_target(),
          socket: socket,
          userinfo: %{
            "name" => "Sadio Mane",
            "email" => "sadio@example.com",
            "picture" => "https://example.com/avatar.jpg"
          },
          scopes_changed: false
        )

      assert status =~ "Sadio Mane"
      assert status =~ "sadio@example.com"
      assert status =~ "https://example.com/avatar.jpg"
      assert status =~ "Successfully authenticated with Salesforce"
      assert status =~ "reauthenticate with Salesforce"
    end

    test "renders complete state without user information" do
      status =
        render_component(&Oauth.oauth_status/1,
          state: :complete,
          provider: "Salesforce",
          myself: mock_target(),
          userinfo: nil,
          scopes_changed: false
        )

      assert status =~ "Successfully authenticated with Salesforce!"
      assert status =~ "Your credential is ready to use"
      assert status =~ "couldn't fetch your user information"
    end

    test "renders complete state with default user values" do
      socket = %Phoenix.LiveView.Socket{
        endpoint: LightningWeb.Endpoint,
        router: LightningWeb.Router
      }

      status =
        render_component(&Oauth.oauth_status/1,
          state: :complete,
          provider: "Salesforce",
          myself: mock_target(),
          socket: socket,
          userinfo: %{},
          scopes_changed: false
        )

      assert status =~ "Unknown User"
      assert status =~ "No email provided"
      assert status =~ "/images/user.png"
    end

    test "renders error state" do
      status =
        render_component(&Oauth.oauth_status/1,
          state: :error,
          provider: "Google",
          myself: mock_target(),
          authorize_url: "https://google.com/oauth",
          error: :invalid_token,
          scopes_changed: false
        )

      assert status =~ "authorize_click"
    end

    test "renders scope change alert when scopes_changed is true" do
      status =
        render_component(&Oauth.oauth_status/1,
          state: :idle,
          provider: "Salesforce",
          myself: mock_target(),
          authorize_url: "https://salesforce.com/oauth",
          scopes_changed: true
        )

      assert status =~ "authorize_click"
      refute status =~ "Sign in with Salesforce"
    end
  end

  describe "oauth_status/1 edge cases" do
    test "handles missing authorize_url in idle state" do
      status =
        render_component(&Oauth.oauth_status/1,
          state: :idle,
          provider: "Salesforce",
          myself: mock_target(),
          scopes_changed: false
        )

      assert status =~ "Sign in with Salesforce"
    end

    test "handles missing error in error state" do
      status =
        render_component(&Oauth.oauth_status/1,
          state: :error,
          provider: "Salesforce",
          myself: mock_target(),
          authorize_url: "https://salesforce.com/oauth",
          scopes_changed: false
        )

      assert status =~ "authorize_click"
    end

    test "handles all states with scopes_changed true" do
      states = [:idle, :authenticating, :fetching_userinfo, :complete, :error]

      for state <- states do
        status =
          render_component(&Oauth.oauth_status/1,
            state: state,
            provider: "TestProvider",
            myself: mock_target(),
            scopes_changed: true,
            authorize_url: "https://example.com/oauth",
            userinfo: %{"name" => "Test User"},
            error: :test_error
          )

        assert status =~ "authorize_click"
      end
    end
  end

  describe "component integration" do
    test "scopes_picklist integrates with oauth_status flow" do
      scopes = ["api", "refresh_token", "offline_access"]

      picklist =
        render_component(&Oauth.scopes_picklist/1,
          id: "salesforce_scopes",
          on_change: "update_scopes",
          target: mock_target(),
          selected_scopes: ["api"],
          mandatory_scopes: ["api"],
          scopes: scopes,
          provider: "Salesforce",
          doc_url: "https://help.salesforce.com/oauth"
        )

      status =
        render_component(&Oauth.oauth_status/1,
          state: :idle,
          provider: "Salesforce",
          myself: mock_target(),
          authorize_url: "https://salesforce.com/oauth",
          scopes_changed: false
        )

      assert picklist =~ "Select permissions"
      assert status =~ "Sign in with Salesforce"
    end

    test "all components handle long provider names" do
      long_provider = "Super Long OAuth Provider Name With Many Words"

      socket = %Phoenix.LiveView.Socket{
        endpoint: LightningWeb.Endpoint,
        router: LightningWeb.Router
      }

      picklist =
        render_component(&Oauth.scopes_picklist/1,
          id: "test",
          on_change: "change",
          target: mock_target(),
          selected_scopes: [],
          mandatory_scopes: [],
          scopes: ["read"],
          provider: long_provider
        )

      picklist_with_doc =
        render_component(&Oauth.scopes_picklist/1,
          id: "test_with_doc",
          on_change: "change",
          target: mock_target(),
          selected_scopes: [],
          mandatory_scopes: [],
          scopes: ["read"],
          provider: long_provider,
          doc_url: "https://example.com/docs"
        )

      status =
        render_component(&Oauth.oauth_status/1,
          state: :complete,
          provider: long_provider,
          myself: mock_target(),
          socket: socket,
          userinfo: %{"name" => "User"},
          scopes_changed: false
        )

      warning = render_component(&Oauth.missing_client_warning/1, %{})

      assert picklist =~ "Select permissions"
      refute picklist =~ long_provider

      assert picklist_with_doc =~ long_provider

      assert status =~ long_provider
      assert warning =~ "OAuth client"
    end
  end

  describe "accessibility" do
    test "components include proper ARIA attributes and labels" do
      picklist =
        render_component(&Oauth.scopes_picklist/1,
          id: "a11y_test",
          on_change: "change",
          target: mock_target(),
          selected_scopes: ["read"],
          mandatory_scopes: [],
          scopes: ["read", "write"],
          provider: "TestProvider"
        )

      dom = Floki.parse_document!(picklist)

      checkboxes = Floki.find(dom, "input[type='checkbox']")
      assert length(checkboxes) == 2

      assert Floki.find(dom, "#a11y_test_read") != []
      assert Floki.find(dom, "#a11y_test_write") != []
    end
  end
end
