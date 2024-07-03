defmodule Lightning.UsageTracking.UserService do
  @moduledoc """
  Returns counts for the various user-related metrics.


  """
  alias Lightning.Repo
  alias Lightning.UsageTracking.UserQueries

  def no_of_users(date) do
    UserQueries.existing_users(date) |> Repo.aggregate(:count)
  end

  def no_of_users(date, user_list) do
    UserQueries.existing_users(date, user_list) |> Repo.aggregate(:count)
  end

  def no_of_active_users(date) do
    UserQueries.active_users(date) |> Repo.aggregate(:count)
  end

  def no_of_active_users(date, user_list) do
    UserQueries.active_users(date, user_list) |> Repo.aggregate(:count)
  end
end
