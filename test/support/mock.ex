defmodule Lightning.Stub do
  @moduledoc false
  @behaviour Lightning.API

  @impl true
  def current_time, do: Lightning.API.current_time()

  @impl true
  def broadcast(topic, msg), do: Lightning.API.broadcast(topic, msg)

  @impl true
  def subscribe(topic), do: Lightning.API.subscribe(topic)

  @doc """
  Resets the current time to the current time.
  """
  def reset_time do
    Lightning.Mock
    |> Mox.stub(:current_time, fn -> DateTime.utc_now() end)
  end

  @doc """
  Freezes the current time to the given time.
  """
  def freeze_time(time) do
    Lightning.Mock
    |> Mox.stub(:current_time, fn -> time end)
  end
end

Mox.defmock(Lightning.Mock, for: Lightning.API)
