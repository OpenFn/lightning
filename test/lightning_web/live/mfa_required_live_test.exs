defmodule LightningWeb.MFARequiredLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.AccountsFixtures

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "Index" do
    test "displays the right copy", %{conn: conn} do
      {:ok, view, html} = live(conn, "/mfa_required")

      assert html =~
               "This project requires all members to enabled multi-factor authentication"

      assert view |> element(~s{[href="/profile"]}) |> has_element?()
    end

    test "redirects to / if user already has mfa enabled", %{
      conn: conn,
      project: project
    } do
      user = user_with_mfa_fixture()
      conn = setup_project_user(conn, project, user, :editor)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/mfa_required")
    end
  end
end
