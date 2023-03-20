defmodule LightningWeb.TokensLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Swoosh.TestAssertions

  describe "Personal Access Tokens" do
    setup :register_and_log_in_user

    test "See an empy page with generate token button", %{conn: conn} do
    end

    test "Generate new token", %{conn: conn} do
    end

    test "See a list of tokens", %{conn: conn} do
      {:ok, _profile_live, html} =
        live(conn, Routes.profile_edit_path(conn, :edit))
    end

    test "Delete an existing token", %{conn: conn} do
    end
  end
end
