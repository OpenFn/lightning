defmodule LightningWeb.TokensLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.{AccountsFixtures}

  setup :register_and_log_in_user

  defp create_api_token(%{user: user}) do
    api_token = api_token_fixture(user)
    %{api_token: api_token}
  end

  describe "Index" do
    test "Access API Tokens page", %{conn: conn} do
      {:ok, token_live, html} = live(conn, ~p"/profile/tokens")

      assert token_live
             |> element("nav#side-menu a", "API Tokens")
             |> has_element?()

      assert html =~ "Personal Access Tokens"
      assert html =~ "No Personal Access Tokens"
      assert html =~ "Get started by creating a new access token."

      assert token_live
             |> element("a", "Generate New Token")
    end

    test "Generate new token", %{conn: conn} do
      {:ok, token_live, _html} = live(conn, ~p"/profile/tokens")

      assert token_live
             |> element("#generate_new_token", "Generate New Token")
             |> render_click() =~ "Token created successfully"

      assert token_live
             |> element("tr[data-entity='new_token']")
             |> has_element?()

      assert token_live |> element("button#copy") |> has_element?()

      assert token_live |> element("button#copy") |> render_click() =~
               "Token copied successfully"

      assert token_live
             |> element("input#new_token")
             |> render()
             |> Floki.parse_fragment!()
             |> Floki.attribute("value")
             |> Floki.text()
             |> String.length() == 539
    end

    test "See a list of tokens", %{conn: conn} do
      {:ok, token_live, _html} = live(conn, ~p"/profile/tokens")

      assert token_live
             |> element("#generate_new_token", "Generate New Token")
             |> render_click() =~ "Token created successfully"

      assert token_live
             |> element("table#tokens")
             |> render()
             |> Floki.parse_fragment!()
             |> Floki.find("code span")
             |> Floki.text(sep: "\n")
             |> String.contains?("...")
    end
  end

  describe "Token modal" do
    setup :create_api_token

    test "Delete an existing token", %{conn: conn, api_token: api_token} do
      {:ok, token_live, _html} = live(conn, ~p"/profile/tokens")

      # find a <tr> that has id of `token-<id>`
      assert token_live
             |> has_element?("tr#token-#{api_token.id}")

      # and then click the thing that is a#delete-token-#token_id
      assert token_live
             |> element("a#delete-token-#{api_token.id}")
             |> render_click() =~ "Any applications or scripts using this token"

      # can see the modal
      assert_patched(
        token_live,
        ~p"/profile/tokens/#{api_token.id}/delete"
      )

      # click confirm
      {:ok, no_token_live, _html} =
        token_live
        |> element("button[phx-click=delete_token]")
        |> render_click()
        |> follow_redirect(conn, ~p"/profile/tokens")

      # assert patched / redirect
      {path, flash} = assert_redirect(token_live)

      assert flash == %{"info" => "Token deleted successfully"}
      assert path == "/profile/tokens"

      # assert we can't see `token-<id>`
      refute no_token_live
             |> has_element?("tr#token-#{api_token.id}")
    end

    test "Users can't delete other users api tokens", %{
      conn: conn
    } do
      another_user_token = api_token_fixture(user_fixture())

      {:ok, _tokens_live, html} =
        live(conn, ~p"/profile/tokens/#{another_user_token.id}/delete")
        |> follow_redirect(conn)

      assert html =~ "You can&#39;t perform this action"
    end
  end
end
