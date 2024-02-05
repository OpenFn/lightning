defmodule Lightning.Extensions.RuntimeLimiterTest do
  use ExUnit.Case

  alias Lightning.Extensions.RuntimeLimiting.Context
  alias Lightning.Extensions.RuntimeLimiter

  test "runtime limit is not exceeded" do
    assert RuntimeLimiter.check_limits(%Context{
             project_id: Ecto.UUID.generate(),
             user_id: Ecto.UUID.generate()
           }) == :ok
  end
end
