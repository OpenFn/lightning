defmodule Lightning.Accounts.SignInAttemptsTest do
  # Not async: the racing processes share the test's connection.
  use Lightning.DataCase, async: false

  alias Lightning.Accounts.SignInAttempts

  defp attempts(email, times),
    do: for(_ <- 1..times, do: SignInAttempts.sign_in_attempt(email))

  defp end_windows do
    Repo.update_all("sign_in_attempts",
      set: [
        window_started_at:
          DateTime.add(DateTime.utc_now(), -16, :minute) |> DateTime.to_naive()
      ]
    )
  end

  test "refuses the eleventh attempt on an address of any length, in any case" do
    email = String.duplicate("a", 100_000) <> "@example.com"

    assert attempts(email, 10) == List.duplicate(:ok, 10)

    assert SignInAttempts.sign_in_attempt(String.upcase(email)) ==
             {:error, :rate_limited}

    assert SignInAttempts.sign_in_attempt("other-" <> email) == :ok
  end

  test "a successful attempt is taken back off the count" do
    attempts("someone@example.com", 9)
    assert SignInAttempts.sign_in_attempt("someone@example.com") == :ok
    assert SignInAttempts.sign_in_succeeded("someone@example.com") == :ok

    assert SignInAttempts.sign_in_attempt("someone@example.com") == :ok

    assert SignInAttempts.sign_in_attempt("someone@example.com") ==
             {:error, :rate_limited}
  end

  test "the count starts again once its window has ended" do
    attempts("someone@example.com", 11)
    end_windows()

    assert attempts("someone@example.com", 10) == List.duplicate(:ok, 10)

    assert SignInAttempts.sign_in_attempt("someone@example.com") ==
             {:error, :rate_limited}
  end

  test "attempts sent together each get their own count" do
    test = self()

    tasks =
      for _ <- 1..40 do
        Task.async(fn ->
          send(test, {:ready, self()})
          receive do: (:go -> SignInAttempts.sign_in_attempt("race@example.com"))
        end)
      end

    for _ <- tasks, do: assert_receive({:ready, _pid})
    for task <- tasks, do: send(task.pid, :go)

    results = Task.await_many(tasks)

    assert Enum.count(results, &(&1 == :ok)) == 10
    assert Enum.count(results, &(&1 == {:error, :rate_limited})) == 30
  end

  test "a pending sign-in gets five tries at its code" do
    results = for _ <- 1..6, do: SignInAttempts.code_attempt("session token")

    assert results == [:ok, :ok, :ok, :ok, :last, :spent]
    assert SignInAttempts.code_attempt("another token") == :ok
  end

  test "pruning deletes the counts whose window has ended" do
    attempts("old@example.com", 3)
    end_windows()
    attempts("new@example.com", 1)

    assert SignInAttempts.perform(%Oban.Job{}) == :ok

    assert Repo.aggregate("sign_in_attempts", :count) == 1
  end
end
