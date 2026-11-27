defmodule Lightning.Accounts.SignInAttemptsTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories
  import Lightning.SignInAttemptHelpers

  alias Lightning.Accounts.SignInAttempts

  @password "hello world!"

  defp mfa_user do
    insert(:user, mfa_enabled: true, user_totp: build(:user_totp))
  end

  defp totp(user),
    do: {:totp, NimbleTOTP.verification_code(user.user_totp.secret)}

  defp start_windows_ago(minutes) do
    Repo.update_all("sign_in_attempts",
      set: [
        window_started_at:
          DateTime.add(DateTime.utc_now(), -minutes, :minute)
          |> DateTime.to_naive()
      ]
    )
  end

  defp end_windows, do: start_windows_ago(16)

  describe "check_password/2" do
    test "answers the account for the right password" do
      user = insert(:user)

      assert {:ok, %{id: id}} =
               SignInAttempts.check_password(user.email, @password)

      assert id == user.id

      assert SignInAttempts.check_password(user.email, "wrong") ==
               {:error, :invalid_credentials}
    end

    test "refuses the eleventh attempt on an address of any length, in any case" do
      email = String.duplicate("a", 100_000) <> "@example.com"

      assert wrong_passwords(email, 10) ==
               List.duplicate({:error, :invalid_credentials}, 10)

      assert {:error, {:rate_limited, seconds}} =
               SignInAttempts.check_password(String.upcase(email), "wrong")

      assert seconds in 1..900

      assert SignInAttempts.check_password("other-" <> email, "wrong") ==
               {:error, :invalid_credentials}
    end

    # Needs a database whose ctype lowercases İ (U+0130) to i, as glibc does and
    # the C locale doesn't; elsewhere there is nothing to show.
    test "every spelling the database treats as one address shares a count" do
      %{rows: [[same?]]} =
        Repo.query!("select 'admİn@x.com'::citext = 'admin@x.com'::citext")

      if same? do
        user = insert(:user, email: "admin@example.com")
        wrong_passwords("admİn@example.com", 5)
        wrong_passwords(user.email, 5)

        assert {:error, {:rate_limited, _seconds}} =
                 SignInAttempts.check_password("admİn@example.com", "wrong")

        assert {:error, {:rate_limited, _seconds}} =
                 SignInAttempts.check_password(user.email, "wrong")
      end
    end

    test "the right password doesn't count, nor clear the failures before it" do
      user = insert(:user)
      wrong_passwords(user.email, 9)

      for _ <- 1..2,
          do:
            assert(
              {:ok, _user} = SignInAttempts.check_password(user.email, @password)
            )

      wrong_passwords(user.email, 1)

      assert {:error, {:rate_limited, _seconds}} =
               SignInAttempts.check_password(user.email, @password)
    end

    test "the count starts again once its window has ended" do
      wrong_passwords("someone@example.com", 11)
      end_windows()

      assert wrong_passwords("someone@example.com", 10) ==
               List.duplicate({:error, :invalid_credentials}, 10)

      assert {:error, {:rate_limited, _seconds}} =
               SignInAttempts.check_password("someone@example.com", "wrong")
    end

    test "a refusal says how many seconds are left in the window" do
      wrong_passwords("clock@example.com", 10)

      assert {:error, {:rate_limited, seconds}} =
               SignInAttempts.check_password("clock@example.com", "wrong")

      assert seconds in 895..900

      start_windows_ago(10)

      assert {:error, {:rate_limited, seconds}} =
               SignInAttempts.check_password("clock@example.com", "wrong")

      assert seconds in 295..301
    end

    test "attempts sent together each get their own count" do
      test = self()

      tasks =
        for _ <- 1..40 do
          Task.async(fn ->
            send(test, {:ready, self()})

            receive do
              :go -> SignInAttempts.check_password("race@example.com", "wrong")
            end
          end)
        end

      for _ <- tasks, do: assert_receive({:ready, _pid})
      for task <- tasks, do: send(task.pid, :go)

      results = Task.await_many(tasks)

      assert Enum.count(results, &(&1 == {:error, :invalid_credentials})) == 10
      assert Enum.count(results, &match?({:error, {:rate_limited, _}}, &1)) == 30
    end
  end

  describe "check_code/3, finishing a pending sign-in" do
    test "accepts the right code" do
      user = mfa_user()

      assert SignInAttempts.check_code(user, totp(user), "session token") == :ok
    end

    test "gives the sign-in five tries, after which even the right code is refused" do
      user = mfa_user()

      tries =
        for _ <- 1..5,
            do:
              SignInAttempts.check_code(user, {:totp, "000000"}, "session token")

      assert tries ==
               List.duplicate({:error, :invalid_credentials}, 4) ++
                 [{:error, :tries_spent}]

      assert SignInAttempts.check_code(user, totp(user), "session token") ==
               {:error, :tries_spent}

      assert SignInAttempts.check_code(user, totp(user), "another token") == :ok
    end

    test "counts wrong codes against the account's limit" do
      user = mfa_user()

      for n <- 1..10,
          do: SignInAttempts.check_code(user, {:totp, "000000"}, "token #{n}")

      assert {:error, {:rate_limited, _seconds}} =
               SignInAttempts.check_code(user, totp(user), "fresh token")
    end
  end

  describe "confirm_password/2, for a signed-in user" do
    test "counts a wrong password and takes a right one back" do
      user = insert(:user)

      assert SignInAttempts.confirm_password(user, "wrong") ==
               {:error, :invalid_credentials}

      assert SignInAttempts.confirm_password(user, @password) == :ok
      assert_attempts_left(user.email, 9)
    end

    test "refuses the right password once the account is limited" do
      user = insert(:user)
      wrong_passwords(user.email, 10)

      assert {:error, {:rate_limited, seconds}} =
               SignInAttempts.confirm_password(user, @password)

      assert seconds in 1..900
    end
  end

  test "check_code/2 checks a code sent with the password" do
    user = mfa_user()

    assert SignInAttempts.check_code(user, {:totp, "000000"}) ==
             {:error, :invalid_credentials}

    assert SignInAttempts.check_code(user, totp(user)) == :ok
  end

  test "pruning deletes the counts whose window has ended" do
    wrong_passwords("old@example.com", 3)
    end_windows()
    wrong_passwords("new@example.com", 1)

    assert SignInAttempts.perform(%Oban.Job{}) == :ok

    assert Repo.aggregate("sign_in_attempts", :count) == 1
  end
end
