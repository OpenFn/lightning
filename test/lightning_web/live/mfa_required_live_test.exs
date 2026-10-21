defmodule LightningWeb.MFARequiredLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "Index" do
    test "shows the page to a user without MFA", %{conn: conn} do
      {:ok, view, html} = live(conn, "/mfa_required")

      assert html =~ "MFA Required for Project"
      # The copy and the /profile links are drawn by React from no props.
      assert page_props(view, "#mfa-required-page") == %{}
    end

    test "redirects to /projects if user already has mfa enabled", %{
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
