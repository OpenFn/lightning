defmodule LightningWeb.KeychainCredentialLiveTest do
  use LightningWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Lightning.Factories

  setup :register_and_log_in_user

  describe "Keychain Credential UI" do
    test "displays keychain credential creation option", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :admin}])

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings#credentials")

      # Check if the keychain credential option exists
      assert has_element?(view, "#option-menu-item-2")

      # Check if the live component exists
      assert has_element?(view, "#new-keychain-credential-modal")
    end

    test "displays keychain credentials in list", %{conn: conn, user: user} do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :admin}])

      credential = insert(:credential, user: user)
      insert(:project_credential, project: project, credential: credential)

      _keychain_credential =
        insert(:keychain_credential,
          project: project,
          created_by: user,
          default_credential: credential
        )

      {:ok, _view, _html} =
        live(conn, ~p"/projects/#{project}/settings#credentials")

      # TODO: Add test for keychain credential display when UI is implemented
      # This would check that the keychain credentials appear in the list
    end
  end

  describe "Permissions" do
    test "non-admin users cannot access keychain credential creation", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :viewer}])

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings#credentials")

      # The create button should be disabled for non-admin users
      disabled_button = has_element?(view, "button[disabled]")
      options_button = has_element?(view, "#options-menu-button")

      assert disabled_button || !options_button,
             "Expected button to be disabled or not present for viewers"
    end
  end
end
