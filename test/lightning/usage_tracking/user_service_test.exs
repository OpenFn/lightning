defmodule Lightning.UsageTracking.UserServiceTest do
  use Lightning.DataCase, async: true

  alias Lightning.UsageTracking.UserService

  @date ~D[2024-02-05]
  describe "no_of_users/1" do
    test "count includes all users created on/before date" do
      _eligible_user_1 =
        insert(:user, inserted_at: ~U[2024-02-05 23:59:59Z])

      _eligible_user_2 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _ineligible_user_after_date =
        insert(
          :user,
          disabled: false,
          inserted_at: ~U[2024-02-06 00:00:01Z]
        )

      assert UserService.no_of_users(@date) == 2
    end
  end

  describe ".no_of_users/2" do
    test "returns subset of user list that exists before report date" do
      eligible_user_1 =
        insert(:user, inserted_at: ~U[2024-02-05 23:59:59Z])

      _eligible_user_2 =
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

      assert UserService.no_of_users(@date, user_list) == 2
    end
  end

  describe ".no_of_active_users/1" do
    test "returns a count of all active, enabled users" do
      within_threshold_date = Date.add(@date, -89)

      {:ok, within_threshold_time, _offset} =
        DateTime.from_iso8601("#{within_threshold_date}T10:00:00Z")

      outside_threshold_date = Date.add(@date, -90)

      {:ok, outside_threshold_time, _offset} =
        DateTime.from_iso8601("#{outside_threshold_date}T10:00:00Z")

      enabled_user_1 =
        insert(
          :user,
          disabled: false,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _active_token_user_1 =
        insert(
          :user_token,
          context: "session",
          inserted_at: within_threshold_time,
          user: enabled_user_1
        )

      enabled_user_2 =
        insert(
          :user,
          disabled: false,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _active_token_user_2 =
        insert(
          :user_token,
          context: "session",
          inserted_at: within_threshold_time,
          user: enabled_user_2
        )

      enabled_user_3 =
        insert(
          :user,
          disabled: false,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _inactive_token =
        insert(
          :user_token,
          context: "session",
          inserted_at: outside_threshold_time,
          user: enabled_user_3
        )

      assert UserService.no_of_active_users(@date) == 2
    end
  end

  describe ".no_of_active_users/2" do
    test "returns active subset of user list" do
      within_threshold_date = Date.add(@date, -89)

      {:ok, within_threshold_time, _offset} =
        DateTime.from_iso8601("#{within_threshold_date}T10:00:00Z")

      outside_threshold_date = Date.add(@date, -90)

      {:ok, outside_threshold_time, _offset} =
        DateTime.from_iso8601("#{outside_threshold_date}T10:00:00Z")

      enabled_user_1 =
        insert(
          :user,
          disabled: false,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _active_token_user_1 =
        insert(
          :user_token,
          context: "session",
          inserted_at: within_threshold_time,
          user: enabled_user_1
        )

      enabled_user_2 =
        insert(
          :user,
          disabled: false,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _active_token_user_2 =
        insert(
          :user_token,
          context: "session",
          inserted_at: within_threshold_time,
          user: enabled_user_2
        )

      enabled_user_3 =
        insert(
          :user,
          disabled: false,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _active_token_user_3 =
        insert(
          :user_token,
          context: "session",
          inserted_at: within_threshold_time,
          user: enabled_user_3
        )

      enabled_user_4 =
        insert(
          :user,
          disabled: false,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _inactive_token =
        insert(
          :user_token,
          context: "session",
          inserted_at: outside_threshold_time,
          user: enabled_user_4
        )

      user_list = [
        enabled_user_1,
        enabled_user_4,
        enabled_user_3
      ]

      assert UserService.no_of_active_users(@date, user_list) == 2
    end
  end
end
