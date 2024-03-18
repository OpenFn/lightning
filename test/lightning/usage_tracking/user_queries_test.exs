defmodule Lightning.UsageTracking.UserQueriesTest do
  use Lightning.DataCase
  
  @date ~D[2024-02-05]

  alias Lightning.Repo
  alias Lightning.UsageTracking.UserQueries

  describe "enabled_users/1" do
    test "includes enabled users created on or before the date" do
      eligible_user_1 = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-05 23:59:59Z]
      )
      eligible_user_2 = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-04 01:00:00Z]
      )
      ineligible_user_disabled = insert(
        :user,
        disabled: true,
        inserted_at: ~U[2024-02-04 01:00:00Z],
        updated_at: ~U[2024-02-04 01:00:00Z]
      )
      ineligible_user_after_date = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-06 00:00:01Z]
      )

      result = UserQueries.enabled_users(@date) |> Repo.all()

      assert result |> contains(eligible_user_1)
      assert result |> contains(eligible_user_2)
      refute result |> contains(ineligible_user_after_date)
      refute result |> contains(ineligible_user_disabled)
    end

    test "includes disabled users who may have been enabled" do
      eligible_user_enabled = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-05 23:59:59Z]
      )
      eligible_user_inserted_before_disabled_after_date_1 = insert(
        :user,
        disabled: true,
        inserted_at: ~U[2024-02-04 01:00:00Z],
        updated_at: ~U[2024-02-06 00:00:00Z]
      )
      eligible_user_inserted_before_disabled_after_date_2 = insert(
        :user,
        disabled: true,
        inserted_at: ~U[2024-02-05 23:59:59Z],
        updated_at: ~U[2024-02-06 00:00:01Z]
      )
      ineligible_user_disabled_inserted_before_disabled_before = insert(
        :user,
        disabled: true,
        inserted_at: ~U[2024-02-04 01:00:00Z],
        updated_at: ~U[2024-02-04 01:00:00Z]
      )
      ineligible_user_disabled_inserted_after_disabled_after_1 = insert(
        :user,
        disabled: true,
        inserted_at: ~U[2024-02-06 00:00:00Z],
        updated_at: ~U[2024-02-06 01:00:00Z]
      )
      ineligible_user_disabled_inserted_after_disabled_after_2 = insert(
        :user,
        disabled: true,
        inserted_at: ~U[2024-02-06 00:00:01Z],
        updated_at: ~U[2024-02-06 01:00:00Z]
      )

      result = UserQueries.enabled_users(@date) |> Repo.all()

      assert(
        result |> contains(eligible_user_enabled)
      )
      assert(
        result |> contains(eligible_user_inserted_before_disabled_after_date_1)
      )
      assert(
        result |> contains(eligible_user_inserted_before_disabled_after_date_2)
      )
      refute(
        result
        |> contains(ineligible_user_disabled_inserted_before_disabled_before)
      )
      refute(
        result
        |> contains(ineligible_user_disabled_inserted_after_disabled_after_1)
      )
      refute(
        result
        |> contains(ineligible_user_disabled_inserted_after_disabled_after_2)
      )
    end
  end

  describe "enabled_users/2" do
    test "returns subset of user list that are enabled on or before the date" do
      eligible_user_1 = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-05 23:59:59Z]
      )
      eligible_user_2 = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-04 01:00:00Z]
      )
      eligible_user_3 = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-04 01:00:00Z]
      )
      ineligible_user_after_date = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-06 00:00:01Z]
      )

      user_list = [
        eligible_user_1,
        ineligible_user_after_date,
        eligible_user_3
      ]

      result = UserQueries.enabled_users(@date, user_list) |> Repo.all()

      assert result |> contains(eligible_user_1)
      assert result |> contains(eligible_user_3)
      refute result |> contains(eligible_user_2)
      refute result |> contains(ineligible_user_after_date)
    end
  end

  describe "active_users/1" do
    test "returns users that have logged in in the last 30 days" do
      enabled_user_1 = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-04 01:00:00Z]
      )
      _active_token = insert(
        :user_token,
        context: "session",
        inserted_at: ~U[2023-11-08 00:00:00Z],
        user: enabled_user_1
      )
      enabled_user_2 = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-04 01:00:00Z]
      )
      _active_token = insert(
        :user_token,
        context: "session",
        inserted_at: ~U[2024-02-05 23:59:59Z],
        user: enabled_user_2
      )
      enabled_user_3 = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-04 01:00:00Z]
      )
      _ineligible_token_older_than_30_days = insert(
        :user_token,
        context: "session",
        inserted_at: ~U[2023-11-07 23:59:59Z],
        user: enabled_user_3
      )
      enabled_user_4 = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-04 01:00:00Z]
      )
      _ineligible_token_newer_than_report_date = insert(
        :user_token,
        context: "session",
        inserted_at: ~U[2024-02-06 00:00:01Z],
        user: enabled_user_4
      )
      enabled_user_5 = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-04 01:00:00Z]
      )
      _ineligible_token_not_session = insert(
        :user_token,
        context: "api",
        inserted_at: ~U[2024-02-05 00:00:01Z],
        user: enabled_user_5
      )

      result = UserQueries.active_users(@date) |> Repo.all()

      assert(
        result |> contains(enabled_user_1)
      )
      assert(
        result |> contains(enabled_user_2)
      )
      refute(
        result |> contains(enabled_user_3)
      )
      refute(
        result |> contains(enabled_user_4)
      )
      refute(
        result |> contains(enabled_user_5)
      )
    end

    test "if user has more than one token, only includes user once" do
      enabled_user_1 = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-04 01:00:00Z]
      )
      _active_token_user_1_1 = insert(
        :user_token,
        context: "session",
        inserted_at: ~U[2023-11-08 00:00:00Z],
        user: enabled_user_1
      )
      _active_token_user_1_2 = insert(
        :user_token,
        context: "session",
        inserted_at: ~U[2023-11-08 00:00:01Z],
        user: enabled_user_1
      )
      enabled_user_2 = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-04 01:00:00Z]
      )
      _active_token_user_2_1 = insert(
        :user_token,
        context: "session",
        inserted_at: ~U[2024-02-05 23:59:59Z],
        user: enabled_user_2
      )

      result = UserQueries.active_users(@date) |> Repo.all()

      assert(
        result |> contains(enabled_user_1)
      )
      assert(
        result |> contains(enabled_user_2)
      )
      assert(length(result) == 2)
    end
  end

  describe "active_users/2" do
    test "returns subset of user list that have logged in the last 90 days" do
      enabled_user_1 = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-04 01:00:00Z]
      )
      _active_token_user_1 = insert(
        :user_token,
        context: "session",
        inserted_at: ~U[2023-11-08 00:00:00Z],
        user: enabled_user_1
      )
      enabled_user_2 = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-04 01:00:00Z]
      )
      _active_token_user_2 = insert(
        :user_token,
        context: "session",
        inserted_at: ~U[2024-02-05 23:59:59Z],
        user: enabled_user_2
      )
      enabled_user_3 = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-04 01:00:00Z]
      )
      _active_token_user_3 = insert(
        :user_token,
        context: "session",
        inserted_at: ~U[2023-11-08 00:00:00Z],
        user: enabled_user_3
      )
      enabled_user_4 = insert(
        :user,
        disabled: false,
        inserted_at: ~U[2024-02-04 01:00:00Z]
      )
      _ineligible_token_older_than_30_days = insert(
        :user_token,
        context: "session",
        inserted_at: ~U[2023-11-07 23:59:59Z],
        user: enabled_user_4
      )

      user_list = [
        enabled_user_1,
        enabled_user_4,
        enabled_user_3
      ]

      result = UserQueries.active_users(@date, user_list) |> Repo.all()

      assert(result |> contains(enabled_user_1))
      assert(result |> contains(enabled_user_3))
      refute(result |> contains(enabled_user_2))
      refute(result |> contains(enabled_user_4))
    end
  end

  defp contains(result, desired_user) do
    result |> Enum.find(fn user -> user.id == desired_user.id end)
  end
end
