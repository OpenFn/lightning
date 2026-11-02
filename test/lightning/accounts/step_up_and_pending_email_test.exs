defmodule Lightning.Accounts.StepUpAndPendingEmailTest do
  use Lightning.DataCase, async: true

  alias Lightning.Accounts
  alias Lightning.Accounts.UserToken
  alias Lightning.Repo

  defp age_token(context, token_query, seconds) do
    inserted_at =
      DateTime.utc_now() |> DateTime.add(-seconds) |> DateTime.truncate(:second)

    Repo.update_all(token_query |> Ecto.Query.where(context: ^context),
      set: [inserted_at: inserted_at]
    )
  end

  describe "sudo_session_expires_at/2" do
    test "is five minutes after the sudo token was made, while that is ahead" do
      user = insert(:user)
      token = Accounts.generate_sudo_session_token(user)

      age_token(
        "sudo_session",
        UserToken.token_and_context_query(token, "sudo_session"),
        60
      )

      expires_at = Accounts.sudo_session_expires_at(user, token)

      assert_in_delta DateTime.diff(expires_at, DateTime.utc_now()), 240, 2
    end

    test "is nil for a lapsed token, another user's, or one that doesn't exist" do
      user = insert(:user)
      lapsed = Accounts.generate_sudo_session_token(user)

      age_token(
        "sudo_session",
        UserToken.token_and_context_query(lapsed, "sudo_session"),
        301
      )

      others = Accounts.generate_sudo_session_token(insert(:user))

      for token <- [lapsed, others, :crypto.strong_rand_bytes(32)] do
        assert Accounts.sudo_session_expires_at(user, token) == nil
      end
    end
  end
end
