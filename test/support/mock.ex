defmodule Lightning.Stub do
  @moduledoc false
  @behaviour Lightning

  @impl true
  def current_time, do: Lightning.API.current_time()

  @impl true
  def broadcast(topic, msg), do: Lightning.API.broadcast(topic, msg)

  @impl true
  def local_broadcast(topic, msg), do: Lightning.API.local_broadcast(topic, msg)

  @impl true
  def subscribe(topic), do: Lightning.API.subscribe(topic)

  @impl true
  def release(), do: Lightning.API.release()

  @doc """
  Resets the current time to the current time.
  """
  def reset_time do
    LightningMock
    |> Mox.stub(:current_time, fn -> DateTime.utc_now() end)
  end

  @doc """
  Freezes the current time to the given time.
  """
  def freeze_time(time) do
    LightningMock
    |> Mox.stub(:current_time, fn -> time end)
  end
end
