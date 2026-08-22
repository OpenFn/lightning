defmodule Lightning.UsageTracking.UserQueriesTest do
  use Lightning.DataCase, async: true

  @date ~D[2024-02-05]

  alias Lightning.Repo
  alias Lightning.UsageTracking.UserQueries

  describe "existing_users/1" do
    test "includes users created on or before the date" do
      eligible_user_1 =
        insert(
          :user,
          disabled: false,
          inserted_at: ~U[2024-02-05 23:59:59Z]
        )

      eligible_user_2 =
        insert(
          :user,
          disabled: true,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      ineligible_user_after_date =
        insert(
          :user,
          inserted_at: ~U[2024-02-06 00:00:01Z]
        )

      result = UserQueries.existing_users(@date) |> Repo.all()

      assert result |> contains(eligible_user_1)
      assert result |> contains(eligible_user_2)
      refute result |> contains(ineligible_user_after_date)
    end
  end

  describe "existing_users/2" do
    test "returns subset of user list inserted on or before the date" do
      eligible_user_1 =
        insert(:user, inserted_at: ~U[2024-02-05 23:59:59Z])

      eligible_user_2 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      eligible_user_3 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      ineligible_user_after_date =
        insert(:user, inserted_at: ~U[2024-02-06 00:00:01Z])

      user_list = [
        eligible_user_1,
        ineligible_user_after_date,
        eligible_user_3
      ]

      result = UserQueries.existing_users(@date, user_list) |> Repo.all()

      assert result |> contains(eligible_user_1)
      assert result |> contains(eligible_user_3)
      refute result |> contains(eligible_user_2)
      refute result |> contains(ineligible_user_after_date)
    end
  end

  describe "active_users/1" do
    test "returns users that have logged in in the last 30 days" do
      user_1 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2023-11-08 00:00:00Z],
          user: user_1
        )

      user_2 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2024-02-05 23:59:59Z],
          user: user_2
        )

      user_3 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _ineligible_token_older_than_30_days =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2023-11-07 23:59:59Z],
          user: user_3
        )

      user_4 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _ineligible_token_newer_than_report_date =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2024-02-06 00:00:01Z],
          user: user_4
        )

      user_5 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _ineligible_token_not_session =
        insert(
          :user_token,
          context: "api",
          inserted_at: ~U[2024-02-05 00:00:01Z],
          user: user_5
        )

      result = UserQueries.active_users(@date) |> Repo.all()

      assert(result |> contains(user_1))
      assert(result |> contains(user_2))
      refute(result |> contains(user_3))
      refute(result |> contains(user_4))
      refute(result |> contains(user_5))
    end

    test "if user has more than one token, only includes user once" do
      user_1 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token_user_1_1 =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2023-11-08 00:00:00Z],
          user: user_1
        )

      _active_token_user_1_2 =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2023-11-08 00:00:01Z],
          user: user_1
        )

      user_2 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token_user_2_1 =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2024-02-05 23:59:59Z],
          user: user_2
        )

      result = UserQueries.active_users(@date) |> Repo.all()

      assert(result |> contains(user_1))
      assert(result |> contains(user_2))
      assert(length(result) == 2)
    end
  end

  describe "active_users/2" do
    test "returns subset of user list that have logged in the last 90 days" do
      user_1 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token_user_1 =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2023-11-08 00:00:00Z],
          user: user_1
        )

      user_2 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token_user_2 =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2024-02-05 23:59:59Z],
          user: user_2
        )

      user_3 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token_user_3 =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2023-11-08 00:00:00Z],
          user: user_3
        )

      user_4 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _ineligible_token_older_than_90_days =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2023-11-07 23:59:59Z],
          user: user_4
        )

      user_list = [
        user_1,
        user_4,
        user_3
      ]

      result = UserQueries.active_users(@date, user_list) |> Repo.all()

      assert(result |> contains(user_1))
      assert(result |> contains(user_3))
      refute(result |> contains(user_2))
      refute(result |> contains(user_4))
    end
  end

  describe "monthly_active_users/1" do
    test "returns users that have logged in in the last 30 days" do
      user_within_window =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2024-01-07 00:00:00Z],
          user: user_within_window
        )

      user_on_report_date =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2024-02-05 23:59:59Z],
          user: user_on_report_date
        )

      user_older_than_30_days =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _ineligible_token_older_than_30_days =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2024-01-06 23:59:59Z],
          user: user_older_than_30_days
        )

      user_newer_than_report_date =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _ineligible_token_newer_than_report_date =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2024-02-06 00:00:01Z],
          user: user_newer_than_report_date
        )

      user_with_non_session_token =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _ineligible_token_not_session =
        insert(
          :user_token,
          context: "api",
          inserted_at: ~U[2024-02-05 00:00:01Z],
          user: user_with_non_session_token
        )

      result = UserQueries.monthly_active_users(@date) |> Repo.all()

      assert(result |> contains(user_within_window))
      assert(result |> contains(user_on_report_date))
      refute(result |> contains(user_older_than_30_days))
      refute(result |> contains(user_newer_than_report_date))
      refute(result |> contains(user_with_non_session_token))
    end

    test "if user has more than one token, only includes user once" do
      user =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token_1 =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2024-01-07 00:00:00Z],
          user: user
        )

      _active_token_2 =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2024-01-07 00:00:01Z],
          user: user
        )

      result = UserQueries.monthly_active_users(@date) |> Repo.all()

      assert(result |> contains(user))
      assert(length(result) == 1)
    end
  end

  describe "monthly_active_users/2" do
    test "returns subset of user list that have logged in the last 30 days" do
      user_in_list_within_window =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2024-01-07 00:00:00Z],
          user: user_in_list_within_window
        )

      user_not_in_list =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2024-01-07 00:00:00Z],
          user: user_not_in_list
        )

      user_in_list_older_than_30_days =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _ineligible_token_older_than_30_days =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2024-01-06 23:59:59Z],
          user: user_in_list_older_than_30_days
        )

      user_list = [
        user_in_list_within_window,
        user_in_list_older_than_30_days
      ]

      result = UserQueries.monthly_active_users(@date, user_list) |> Repo.all()

      assert(result |> contains(user_in_list_within_window))
      refute(result |> contains(user_not_in_list))
      refute(result |> contains(user_in_list_older_than_30_days))
    end
  end

  defp contains(result, desired_user) do
    result |> Enum.find(fn user -> user.id == desired_user.id end)
  end
end
