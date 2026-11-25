defmodule Lightning.UsageTracking.UserQueriesTest do
  use Lightning.DataCase, async: true

  alias Lightning.Repo
  alias Lightning.UsageTracking.UserQueries

  @date ~D[2024-02-05]
  @end_of_report_date ~U[2024-02-05 23:59:59Z]
  @after_report_date ~U[2024-02-06 00:00:01Z]

  describe "existing_users/1" do
    test "includes users created on or before the date, disabled or not" do
      on_date = insert(:user, inserted_at: @end_of_report_date)

      disabled =
        insert(:user, disabled: true, inserted_at: ~U[2024-02-04 01:00:00Z])

      _after_date = insert(:user, inserted_at: @after_report_date)

      assert ids(UserQueries.existing_users(@date)) == ids([on_date, disabled])
    end
  end

  describe "existing_users/2" do
    test "returns the subset of the user list created on or before the date" do
      in_list = insert(:user, inserted_at: @end_of_report_date)
      _not_in_list = insert(:user, inserted_at: @end_of_report_date)
      in_list_after_date = insert(:user, inserted_at: @after_report_date)

      query = UserQueries.existing_users(@date, [in_list, in_list_after_date])

      assert ids(query) == ids([in_list])
    end
  end

  # active_users (90 days) and monthly_active_users (30 days) share one query
  # and differ only in the window, so both run the same cases.
  for {fun, days, first_in_window, last_before_window} <- [
        {:active_users, 90, ~U[2023-11-08 00:00:00Z], ~U[2023-11-07 23:59:59Z]},
        {:monthly_active_users, 30, ~U[2024-01-07 00:00:00Z],
         ~U[2024-01-06 23:59:59Z]}
      ] do
    describe "#{fun}/1" do
      test "counts logins in the last #{days} days" do
        first = with_login(unquote(Macro.escape(first_in_window)))
        last = with_login(@end_of_report_date)
        _before = with_login(unquote(Macro.escape(last_before_window)))
        _after = with_login(@after_report_date)

        assert ids(UserQueries.unquote(fun)(@date)) == ids([first, last])
      end

      test "counts API token use in the last #{days} days" do
        first = with_api_use(unquote(Macro.escape(first_in_window)))
        last = with_api_use(@end_of_report_date)
        _before = with_api_use(unquote(Macro.escape(last_before_window)))
        _after = with_api_use(@after_report_date)
        _never_used = with_api_use(nil)

        assert ids(UserQueries.unquote(fun)(@date)) == ids([first, last])
      end

      test "ignores other token types and counts each user once" do
        _reset_password =
          with_token(context: "reset_password", inserted_at: @end_of_report_date)

        user = with_login(@end_of_report_date)

        insert(:user_token,
          context: "session",
          inserted_at: @end_of_report_date,
          user: user
        )

        insert(:user_token,
          context: "api",
          last_used_at: usec(@end_of_report_date),
          user: user
        )

        assert ids(UserQueries.unquote(fun)(@date)) == ids([user])
      end
    end

    describe "#{fun}/2" do
      test "returns the subset of the user list active in the last #{days} days" do
        in_list = with_login(@end_of_report_date)
        _not_in_list = with_login(@end_of_report_date)
        in_list_inactive = with_login(unquote(Macro.escape(last_before_window)))

        assert ids(UserQueries.unquote(fun)(@date, [in_list, in_list_inactive])) ==
                 ids([in_list])
      end
    end
  end

  defp with_login(at), do: with_token(context: "session", inserted_at: at)

  defp with_api_use(at),
    do:
      with_token(
        context: "api",
        inserted_at: ~U[2023-01-01 00:00:00Z],
        last_used_at: at && usec(at)
      )

  # The user predates every window, so only the token decides whether they count.
  defp with_token(attrs) do
    user = insert(:user, inserted_at: ~U[2023-01-01 00:00:00Z])
    insert(:user_token, Keyword.put(attrs, :user, user))
    user
  end

  # last_used_at is :utc_datetime_usec, which needs microsecond precision.
  defp usec(datetime), do: %{datetime | microsecond: {0, 6}}

  defp ids(%Ecto.Query{} = query), do: query |> Repo.all() |> ids()
  defp ids(users), do: users |> Enum.map(& &1.id) |> Enum.sort()
end
