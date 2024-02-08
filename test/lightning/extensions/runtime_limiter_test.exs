defmodule Lightning.Extensions.UsageLimiterTest do
  use ExUnit.Case

  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Extensions.UsageLimiter

  test "runtime limit is not exceeded" do
    assert UsageLimiter.check_limits(%Context{
             project_id: Ecto.UUID.generate(),
             user_id: Ecto.UUID.generate()
           }) == :ok
  end
end
