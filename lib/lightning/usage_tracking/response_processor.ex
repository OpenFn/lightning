defmodule Lightning.UsageTracking.ResponseProcessor do
  @moduledoc """
  Utility module to abstract deaing with some of the Tesla plumbing

  """
  def successful?(%Tesla.Env{status: status}) do
    status >= 200 && status < 300
  end

  def successful?(_response), do: false
end
