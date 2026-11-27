defmodule Lightning.Accounts.SignInAttemptsTest do
  use ExUnit.Case, async: true

  alias Lightning.Accounts.SignInAttempts

  test "a pending sign-in has five tries at its code, the fifth its last" do
    session_token = :crypto.strong_rand_bytes(32)

    tries = for _try <- 1..6, do: SignInAttempts.code_attempt(session_token)

    assert tries == [:ok, :ok, :ok, :ok, :last, :spent]
  end

  test "an address of any length, in any case, counts as one account" do
    unique = System.unique_integer([:positive])
    email = "#{unique}#{String.duplicate("a", 100_000)}@example.com"

    for _failure <- 1..10, do: SignInAttempts.failed(email)

    assert SignInAttempts.check(String.upcase(email)) == {:error, :rate_limited}
    assert SignInAttempts.check("other-" <> email) == :ok
  end
end
