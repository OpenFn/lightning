defmodule LightningWeb.OauthComponentsTest do
  use LightningWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias LightningWeb.Components.Oauth
  alias LightningWeb.Components.Oauth.{ActionButton, ErrorResponse}

  defp mock_target, do: "test-target"

  describe "ActionButton struct" do
    test "creates valid ActionButton with all parameters" do
      button =
        ActionButton.new("test-id", "Test Text", mock_target(), "test_click")

      assert button.id == "test-id"
      assert button.text == "Test Text"
      assert button.target == mock_target()
      assert button.click == "test_click"
    end

    test "validates string parameters with guards" do
      assert_raise FunctionClauseError, fn ->
        ActionButton.new(123, "Test Text", mock_target(), "test_click")
      end

      assert_raise FunctionClauseError, fn ->
        ActionButton.new("test-id", 123, mock_target(), "test_click")
      end

      assert_raise FunctionClauseError, fn ->
        ActionButton.new("test-id", "Test Text", mock_target(), 123)
      end
    end
  end

  describe "ErrorResponse struct" do
    test "creates valid ErrorResponse" do
      response = ErrorResponse.new("Test Header", :reauthorize, "Test message")

      assert response.header == "Test Header"
      assert response.action == :reauthorize
      assert response.message == "Test message"
    end
  end

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
  end

  describe "authorize_button/1" do
    test "renders OAuth authorization button" do
      button =
        render_component(&Oauth.authorize_button/1,
          authorize_url: "https://example.com/oauth",
          myself: mock_target(),
          provider: "GitHub"
        )

      assert button =~ "https://example.com/oauth"
      assert button =~ "Sign in with GitHub"
      assert button =~ "authorize_click"
      assert button =~ "authorize-button"
    end
  end

  describe "userinfo/1" do
    test "renders user information with avatar and details" do
      socket = %Phoenix.LiveView.Socket{
        router: LightningWeb.Router,
        endpoint: LightningWeb.Endpoint
      }

      userinfo =
        render_component(&Oauth.userinfo/1,
          userinfo: %{
            "name" => "John Doe",
            "email" => "john@example.com",
            "picture" => "https://example.com/avatar.jpg"
          },
          myself: mock_target(),
          authorize_url: "https://example.com/oauth",
          socket: socket
        )

      assert userinfo =~ "John Doe"
      assert userinfo =~ "john@example.com"
      assert userinfo =~ "https://example.com/avatar.jpg"
      assert userinfo =~ "/images/user.png"
    end
  end

  describe "success_message/1" do
    test "renders success message with reauthorization link when revocation available" do
      message =
        render_component(&Oauth.success_message/1,
          revocation: :available,
          myself: mock_target()
        )

      assert message =~ "Success"
      assert message =~ "revoke and reauthenticate"
      assert message =~ "re_authorize_click"
    end

    test "renders success message without reauthorization link when revocation unavailable" do
      message =
        render_component(&Oauth.success_message/1,
          revocation: :unavailable,
          myself: mock_target()
        )

      assert message =~ "Success"
      assert message =~ "third party apps section"
      refute message =~ "re_authorize_click"
    end
  end

  describe "reauthorize_banner/1" do
    test "renders reauthorization banner with provider-specific text" do
      banner =
        render_component(&Oauth.reauthorize_banner/1,
          provider: "GitHub",
          authorize_url: "https://example.com/oauth",
          myself: mock_target()
        )

      assert banner =~ "Reauthentication required"
      assert banner =~ "Reauthenticate with GitHub"
      assert banner =~ "authorize_click"
      assert banner =~ "scopes (i.e., permissions)"
    end
  end

  describe "missing_client_warning/1" do
    test "renders OAuth client not found warning" do
      warning = render_component(&Oauth.missing_client_warning/1, %{})

      assert warning =~ "OAuth client not found"
      assert warning =~ "The associated Oauth client"
      assert warning =~ "cannot be found"
    end
  end

  describe "alert_block/1" do
    test "renders missing_required alert with reauthorization" do
      changeset =
        create_test_changeset(:missing_refresh_token, %{
          existing_token_available: false
        })

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: changeset,
          provider: "Salesforce",
          myself: mock_target()
        )

      assert alert =~ "Missing Refresh Token"
      assert alert =~ "Please reauthorize to provide OpenFn"
      assert alert =~ "Test error message"
      assert alert =~ "authorize_click"
    end

    test "renders missing_required alert with revocation endpoint" do
      changeset =
        create_test_changeset(:missing_refresh_token, %{
          existing_token_available: false
        })

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: changeset,
          provider: "Salesforce",
          revocation_endpoint: "https://example.com/revoke",
          myself: mock_target()
        )

      assert alert =~ "re_authorize_click"
    end

    test "renders missing_required alert with use_existing action" do
      changeset =
        create_test_changeset(:missing_refresh_token, %{
          existing_token_available: true
        })

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: changeset,
          provider: "Salesforce",
          myself: mock_target()
        )

      assert alert =~ "Use Existing Credential"
      assert alert =~ "cancel_click"
    end

    test "renders token_failed alert" do
      alert =
        render_component(&Oauth.alert_block/1,
          type: :token_failed,
          myself: mock_target()
        )

      assert alert =~ "Something went wrong"
      assert alert =~ "Failed retrieving the token from the provider"
      assert alert =~ "Try again"
      assert alert =~ "re_authorize_click"
    end

    test "renders refresh_failed alert" do
      alert =
        render_component(&Oauth.alert_block/1,
          type: :refresh_failed,
          myself: mock_target()
        )

      assert alert =~ "Something went wrong"
      assert alert =~ "Failed renewing your access token"
      assert alert =~ "Request new token"
      assert alert =~ "re_authorize_click"
    end

    test "renders userinfo_failed alert" do
      alert =
        render_component(&Oauth.alert_block/1,
          type: :userinfo_failed,
          myself: mock_target()
        )

      assert alert =~ "couldn't fetch your user information"
      assert alert =~ "Try again"
      assert alert =~ "try_userinfo_again"
    end

    test "renders code_failed alert" do
      alert =
        render_component(&Oauth.alert_block/1,
          type: :code_failed,
          myself: mock_target()
        )

      assert alert =~ "Something went wrong"
      assert alert =~ "Failed retrieving authentication code"
      assert alert =~ "Reauthorize"
      assert alert =~ "re_authorize_click"
    end

    test "renders revoke_failed alert" do
      alert =
        render_component(&Oauth.alert_block/1,
          type: :revoke_failed,
          myself: mock_target()
        )

      assert alert =~ "Something went wrong"
      assert alert =~ "Token revocation failed"
      assert alert =~ "Authorize again"
      assert alert =~ "authorize_click"
    end

    test "renders fetching_userinfo alert" do
      alert =
        render_component(&Oauth.alert_block/1,
          type: :fetching_userinfo,
          myself: mock_target()
        )

      assert alert =~ "Attempting to fetch user information"
    end
  end

  describe "error categorization" do
    test "categorizes missing scopes error with no missing scopes" do
      changeset = create_test_changeset(:missing_scopes, %{missing_scopes: []})

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: changeset,
          provider: "GitHub",
          myself: mock_target()
        )

      assert alert =~ "Missing Required Permissions"
      assert alert =~ "Some required permissions were not granted"
    end

    test "categorizes missing scopes error with single missing scope" do
      changeset =
        create_test_changeset(:missing_scopes, %{missing_scopes: ["read:user"]})

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: changeset,
          provider: "GitHub",
          myself: mock_target()
        )

      assert alert =~ "Missing Required Permission"
      assert alert =~ "&#39;read:user&#39; permission was not granted"
    end

    test "categorizes missing scopes error with multiple missing scopes" do
      changeset =
        create_test_changeset(:missing_scopes, %{
          missing_scopes: ["read:user", "write:repo"]
        })

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: changeset,
          provider: "GitHub",
          myself: mock_target()
        )

      assert alert =~ "Missing Required Permissions"
      assert alert =~ "&#39;read:user&#39;, &#39;write:repo&#39;"
    end

    test "categorizes invalid_oauth_response error" do
      changeset = create_test_changeset(:invalid_oauth_response)

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: changeset,
          provider: "GitHub",
          myself: mock_target()
        )

      assert alert =~ "Invalid OAuth Response"
      assert alert =~ "authorization response from GitHub is invalid"
    end

    test "categorizes invalid_token_format error" do
      changeset = create_test_changeset(:invalid_token_format)

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: changeset,
          provider: "GitHub",
          myself: mock_target()
        )

      assert alert =~ "Invalid Token Format"
      assert alert =~ "OAuth token received from GitHub is in an invalid format"
    end

    test "categorizes missing_token_data error" do
      changeset = create_test_changeset(:missing_token_data)

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: changeset,
          provider: "GitHub",
          myself: mock_target()
        )

      assert alert =~ "Authorization Required"
      assert alert =~ "Please complete the OAuth authorization process"
    end

    test "categorizes missing_access_token error" do
      changeset = create_test_changeset(:missing_access_token)

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: changeset,
          provider: "GitHub",
          myself: mock_target()
        )

      assert alert =~ "Missing Access Token"
      assert alert =~ "missing the required access token"
    end

    test "categorizes missing_expiration error" do
      changeset = create_test_changeset(:missing_expiration)

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: changeset,
          provider: "GitHub",
          myself: mock_target()
        )

      assert alert =~ "Invalid Token Response"
      assert alert =~ "missing expiration information"
    end

    test "categorizes unknown error type" do
      changeset = create_test_changeset(:unknown_error_type)

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: changeset,
          provider: "GitHub",
          myself: mock_target()
        )

      assert alert =~ "OAuth Error"
      assert alert =~ "Please try authorizing with GitHub again"
    end

    test "handles nil error type" do
      changeset = create_test_changeset(nil)

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: changeset,
          provider: "GitHub",
          myself: mock_target()
        )

      assert alert =~ "OAuth Error"
      assert alert =~ "Please try authorizing with GitHub again"
    end

    test "handles nil provider" do
      changeset = create_test_changeset(:missing_refresh_token)

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: changeset,
          myself: mock_target()
        )

      assert alert =~ "your provider"
    end

    test "handles malformed changeset" do
      malformed_changeset = %Ecto.Changeset{
        data: %Lightning.Credentials.Credential{},
        changes: %{},
        errors: [],
        valid?: true
      }

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: malformed_changeset,
          myself: mock_target()
        )

      assert alert =~ "OAuth authorization failed"
    end

    test "handles changeset without oauth_token error" do
      changeset =
        %Lightning.Credentials.Credential{}
        |> Ecto.Changeset.cast(%{}, [])
        |> Ecto.Changeset.add_error(:other_field, "Some other error")

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: changeset,
          myself: mock_target()
        )

      assert alert =~ "OAuth authorization failed"
    end
  end

  describe "default fallback behavior" do
    test "handles unknown suggested action with help fallback" do
      changeset =
        create_test_changeset(:some_custom_error_that_returns_unknown_action)

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: changeset,
          myself: mock_target()
        )

      assert alert =~ "OAuth Error"
    end
  end

  describe "edge cases" do
    test "handles empty error details" do
      changeset = create_test_changeset(:missing_scopes, %{})

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: changeset,
          provider: "GitHub",
          myself: mock_target()
        )

      assert alert =~ "Missing Required Permissions"
    end

    test "handles nil error details" do
      changeset = create_test_changeset(:missing_scopes, nil)

      alert =
        render_component(&Oauth.alert_block/1,
          type: :missing_required,
          changeset: changeset,
          provider: "GitHub",
          myself: mock_target()
        )

      assert alert =~ "Missing Required Permissions"
    end
  end

  defp create_test_changeset(error_type, error_details \\ %{}) do
    %Lightning.Credentials.Credential{}
    |> Ecto.Changeset.cast(%{}, [])
    |> Ecto.Changeset.put_change(:oauth_error_type, error_type)
    |> Ecto.Changeset.put_change(:oauth_error_details, error_details)
    |> Ecto.Changeset.add_error(:oauth_token, "Test error message")
  end
end
