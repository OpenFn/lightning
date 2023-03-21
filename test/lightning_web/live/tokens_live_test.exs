defmodule LightningWeb.TokensLiveTest do
  # alias Lightning.Accounts
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  # defp mask_token(token) do
  #   length = String.length(token)
  #   masked_length = length - 10
  #   mask = String.duplicate("*", masked_length)

  #   Regex.replace(~r/^(.{#{masked_length}})/, token, mask)
  #   |> String.slice(225, masked_length)
  # end

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
             |> element("div[data-entity='new_token']")
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
             |> String.length() == 275
    end

    # test "See a list of tokens", %{conn: conn, user: user} do
    #   {:ok, _token_live, html} = live(conn, ~p"/profile/tokens")

    #   tokens =
    #     Accounts.list_api_tokens(user)
    #     |> Enum.map(fn ut ->
    #       %{
    #         "id" => ut.id,
    #         "token" => mask_token(ut.token),
    #         "inserted_at" => ut.inserted_at
    #       }
    #     end)

    #   assert html =~ tokens
    # end

    # test "Delete an existing token", %{conn: conn} do
    # end
  end
end
