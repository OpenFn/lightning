defmodule Lightning.UsageTracking.ResponseProcessor do
  @moduledoc """
  Utility module to abstract dealing with some of the Tesla plumbing

  """
  def successful?({:ok, %Tesla.Env{status: status}}) do
    status >= 200 && status < 300
  end

  def successful?(_response), do: false

  def successful_200?({:ok, %Tesla.Env{status: 200}}), do: true
  def successful_200?(_response), do: false
end
