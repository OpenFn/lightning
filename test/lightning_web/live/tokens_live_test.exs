defmodule LightningWeb.TokensLiveTest do
  # alias Lightning.Accounts
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "Personal Access Tokens" do
    test "API Tokens navigation", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/profile/tokens")

      assert index_live
             |> element("nav#side-menu a", "API Tokens")
             |> has_element?()
    end

    test "Empty page if there are not tokens", %{conn: conn} do
      {:ok, index_live, html} = live(conn, ~p"/profile/tokens")

      assert html =~ "Personal Access Tokens"
      assert html =~ "No Personal Access Tokens"
      assert html =~ "Get started by creating a new access token."

      assert index_live
             |> element("a", "Generate New Token")
    end

    # Generate new token test
    test "Generate new token", %{conn: conn} do
      {:ok, index_live, html} = live(conn, ~p"/profile/tokens")

      index_live
      |> element("a", "Generate New Token")
      |> render_click()

      refute html =~ "No Personal Access Tokens"

      assert html =~
               "Make sure to copy your token now as you will not be able to see it again."
    end

    # test "See a list of tokens", %{conn: conn, user: user} do
    #   {:ok, _profile_live, html} = live(conn, ~p"/profile/tokens")
    #   token1 = Accounts.generate_api_token(user)
    #   token2 = Accounts.generate_api_token(user)
    #   assert html =~ "Personal Access Tokens"
    # end

    # test "Delete an existing token", %{conn: conn} do
    # end
  end
end
