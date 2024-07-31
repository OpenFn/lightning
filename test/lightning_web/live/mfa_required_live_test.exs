defmodule LightningWeb.MFARequiredLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "Index" do
    test "displays the right copy", %{conn: conn} do
      {:ok, view, html} = live(conn, "/mfa_required")

      assert html =~
               "This project requires all members to use multi-factor authentication."

      assert view |> element(~s{[href="/profile"]}) |> has_element?()
    end

    test "redirects to / if user already has mfa enabled", %{
      conn: conn,
      project: project
    } do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))
      conn = setup_project_user(conn, project, user, :editor)

      assert {:error, {:redirect, %{to: "/projects"}}} =
               live(conn, "/mfa_required")
    end
  end
end
