defmodule FakeRambo do
  @moduledoc """
  Mock implementation of Rambo

  Uses the current process to retrieve overridden responses.
  """
  defmodule Helpers do
    def stub_run(res) do
      Process.put(:res, res)
    end
  end

  def run(command, args, opts) do
    send(self(), {command, args, opts})
    Process.get(:res, {:ok, %{out: "", status: 0}})
  end
end
