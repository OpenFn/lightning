defmodule Lightning.SignInAttemptHelpers do
  @moduledoc """
  Helpers for tests of the sign-in attempt limit, written in terms of what a
  person sees rather than how the attempts are stored.
  """
  import ExUnit.Assertions
  import Plug.Conn, only: [get_resp_header: 2]

  alias Lightning.Accounts.SignInAttempts

  @doc "Sends `times` wrong passwords for `email`, returning each answer."
  def wrong_passwords(email, times),
    do: for(_ <- 1..times, do: SignInAttempts.check_password(email, "wrong"))

  @doc """
  Asserts the account with `email` has exactly `left` guesses before it is
  refused: `left` more wrong passwords are answered, and the next is refused.
  Uses up the account's guesses, so call it last.
  """
  def assert_attempts_left(email, left) do
    if left > 0 do
      assert wrong_passwords(email, left) ==
               List.duplicate({:error, :invalid_credentials}, left)
    end

    assert {:error, {:rate_limited, _seconds}} =
             SignInAttempts.check_password(email, "wrong")
  end

  @doc "Asserts a refusal at the limit says how long to wait, within the window."
  def assert_retry_after(conn) do
    assert [seconds] = get_resp_header(conn, "retry-after")
    assert String.to_integer(seconds) in 1..900
    conn
  end
end
