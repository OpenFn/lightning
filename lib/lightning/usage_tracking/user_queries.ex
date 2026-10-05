defmodule Lightning.UsageTracking.UserQueries do
  @moduledoc """
  Contains queries used to determine user-related metrics.


  """
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Accounts.UserToken

  # Trailing window (in days) used for the two active-user metrics. The 90-day
  # figure is the original `no_of_active_users` series; the 30-day figure backs
  # the standard SaaS "monthly active users" (MAU) metric.
  @active_window_days 90
  @monthly_active_window_days 30

  def existing_users(date) do
    report_time = report_date_as_time(date)

    from u in User, where: u.inserted_at <= ^report_time
  end

  def existing_users(date, user_list) do
    existing_users(date) |> filter_by_users(user_list)
  end

  def active_users(date) do
    active_users_within(date, @active_window_days)
  end

  def active_users(date, user_list) do
    active_users_within(date, @active_window_days) |> filter_by_users(user_list)
  end

  def monthly_active_users(date) do
    active_users_within(date, @monthly_active_window_days)
  end

  def monthly_active_users(date, user_list) do
    active_users_within(date, @monthly_active_window_days)
    |> filter_by_users(user_list)
  end

  defp active_users_within(date, window_days) do
    report_time = report_date_as_time(date)

    {:ok, threshold_time, _offset} =
      date
      |> Date.add(-window_days)
      |> then(&"#{&1}T23:59:59Z")
      |> DateTime.from_iso8601()

    from eu in existing_users(date),
      distinct: eu.id,
      join: ut in UserToken,
      on: ut.user_id == eu.id,
      where: ut.context == "session",
      where: ut.inserted_at > ^threshold_time and ut.inserted_at <= ^report_time
  end

  defp filter_by_users(query, user_list) do
    list_ids = user_list |> Enum.map(& &1.id)

    from u in query, where: u.id in ^list_ids
  end

  defp report_date_as_time(date) do
    {:ok, datetime, _offset} = "#{date}T23:59:59Z" |> DateTime.from_iso8601()

    datetime
  end
end
