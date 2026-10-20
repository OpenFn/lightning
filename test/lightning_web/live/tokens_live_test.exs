defmodule LightningWeb.TokensLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.{AccountsFixtures}

  setup :register_and_log_in_user

  defp create_api_token(%{user: user}) do
    api_token = api_token_fixture(user)
    %{api_token: api_token}
  end

  # The page is drawn by React from these data attributes.
  defp page_data(live, attribute) do
    live
    |> element("#tokens-page")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.attribute(attribute)
    |> List.first()
  end

  defp tokens(live), do: live |> page_data("data-tokens") |> Jason.decode!()

  # Sends an event the way the React page does.
  defp push_page_event(live, event, payload \\ %{}) do
    live |> element("#tokens-page") |> render_hook(event, payload)
  end

  describe "Index" do
    test "Access API Tokens page", %{conn: conn} do
      {:ok, token_live, html} = live(conn, ~p"/profile/tokens", on_error: :raise)

      assert token_live
             |> element("nav#side-menu a", "API Tokens")
             |> has_element?()

      assert html =~ "Personal Access Tokens"
      assert tokens(token_live) == []
    end

    test "Generate new token", %{conn: conn} do
      {:ok, token_live, _html} =
        live(conn, ~p"/profile/tokens", on_error: :raise)

      assert push_page_event(token_live, "generate_new_token") =~
               "Token created successfully"

      assert token_live |> page_data("data-new-token") |> String.length() ==
               539
    end

    test "See a list of tokens", %{conn: conn} do
      {:ok, token_live, _html} =
        live(conn, ~p"/profile/tokens", on_error: :raise)

      push_page_event(token_live, "generate_new_token")

      assert [%{"masked" => "..." <> _, "lastUsedAt" => nil}] =
               tokens(token_live)
    end
  end

  describe "unconfirmed account" do
    setup do
      Mox.stub(Lightning.MockConfig, :check_flag?, fn
        :require_email_verification -> true
        flag -> Lightning.Config.API.check_flag?(flag)
      end)

      :ok
    end

    test "sees the confirmation banner", %{conn: conn} do
      user =
        Lightning.Factories.insert(:user,
          confirmed_at: nil,
          inserted_at: DateTime.utc_now()
        )

      {:ok, view, _html} =
        conn |> log_in_user(user) |> live(~p"/profile/tokens", on_error: :raise)

      assert has_element?(view, "#account-confirmation-alert")
    end
  end

  describe "Token modal" do
    setup :create_api_token

    test "Delete an existing token", %{conn: conn, api_token: api_token} do
      {:ok, token_live, _html} =
        live(conn, ~p"/profile/tokens/#{api_token.id}/delete", on_error: :raise)

      assert [%{"id" => id}] = tokens(token_live)
      assert id == api_token.id
      assert page_data(token_live, "data-token-id") == api_token.id

      assert push_page_event(token_live, "delete_token", %{"id" => api_token.id}) =~
               "Token deleted successfully"

      assert_reply(token_live, reply)
      assert reply == %{}
      assert_patch(token_live, ~p"/profile/tokens")
      assert tokens(token_live) == []
      assert render(token_live) =~ "Token deleted successfully"
    end

    test "can't delete after cancelling the delete modal", %{
      conn: conn,
      api_token: api_token
    } do
      {:ok, token_live, _html} =
        live(conn, ~p"/profile/tokens/#{api_token.id}/delete", on_error: :raise)

      render_patch(token_live, ~p"/profile/tokens")

      push_page_event(token_live, "delete_token", %{"id" => api_token.id})

      assert_reply(token_live, %{error: "You can't perform this action"})
      assert Lightning.Repo.get(Lightning.Accounts.UserToken, api_token.id)
    end

    test "deleting a token that's gone since the modal opened is refused", %{
      conn: conn,
      api_token: api_token
    } do
      {:ok, token_live, _html} =
        live(conn, ~p"/profile/tokens/#{api_token.id}/delete", on_error: :raise)

      Lightning.Repo.delete!(api_token)

      push_page_event(token_live, "delete_token", %{"id" => api_token.id})

      assert_reply(token_live, %{error: "You can't perform this action"})
      assert_patch(token_live, ~p"/profile/tokens")
    end

    test "the delete page for a token that's gone goes back to the list", %{
      conn: conn,
      api_token: api_token
    } do
      Lightning.Repo.delete!(api_token)

      {:ok, _tokens_live, html} =
        live(conn, ~p"/profile/tokens/#{api_token.id}/delete", on_error: :raise)
        |> follow_redirect(conn, ~p"/profile/tokens")

      assert html =~ "You can&#39;t perform this action"
    end

    test "can't delete without the delete modal open", %{
      conn: conn,
      api_token: api_token
    } do
      {:ok, token_live, _html} =
        live(conn, ~p"/profile/tokens", on_error: :raise)

      refute page_data(token_live, "data-token-id")

      push_page_event(token_live, "delete_token", %{"id" => api_token.id})

      assert_reply(token_live, %{error: "You can't perform this action"})
      assert_patch(token_live, ~p"/profile/tokens")
      assert render(token_live) =~ "You can&#39;t perform this action"
      assert Lightning.Repo.get(Lightning.Accounts.UserToken, api_token.id)
    end

    test "Users can't delete other users api tokens", %{
      conn: conn
    } do
      another_user_token = api_token_fixture(user_fixture())

      {:ok, _tokens_live, html} =
        live(conn, ~p"/profile/tokens/#{another_user_token.id}/delete",
          on_error: :raise
        )
        |> follow_redirect(conn)

      assert html =~ "You can&#39;t perform this action"
    end

    test "rejects deleting another user's token via a tampered event id", %{
      conn: conn,
      api_token: api_token
    } do
      # a token owned by a different user
      other_token = api_token_fixture(user_fixture())

      # open the delete modal for the current user's own token (this passes the
      # :delete action's ownership policy)
      {:ok, tokens_live, _html} =
        live(conn, ~p"/profile/tokens/#{api_token.id}/delete", on_error: :raise)

      # fire delete but with the foreign token's id
      push_page_event(tokens_live, "delete_token", %{"id" => other_token.id})

      assert_reply(tokens_live, %{error: "You can't perform this action"})
      assert_patch(tokens_live, ~p"/profile/tokens")
      assert render(tokens_live) =~ "You can&#39;t perform this action"

      # the request is rejected: neither token is deleted (no silent substitution)
      assert Lightning.Repo.get(Lightning.Accounts.UserToken, other_token.id)
      assert Lightning.Repo.get(Lightning.Accounts.UserToken, api_token.id)
    end
  end
end
