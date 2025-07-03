defmodule FakeRambo do
  @moduledoc """
  Mock implementation of Rambo

  Uses the current process to retrieve overridden responses.
  """
  defmodule Helpers do
    def stub_run(res) do
      Cachex.start_link(:fake_rambo_cache)
      Cachex.put(:fake_rambo_cache, :res, res)
    end
  end

  def run(command, args, opts) do
    send(self(), {command, args, opts})

    case Cachex.get(:fake_rambo_cache, :res) do
      {:ok, nil} -> {:ok, %{out: "", status: 0}}
      {:ok, res} -> res
      {:error, _} -> {:ok, %{out: "", status: 0}}
    end
  end
end
