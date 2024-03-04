defmodule Lightning.Extensions.UsageLimiterTest do
  use ExUnit.Case, async: true

  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Extensions.UsageLimiter

  describe "check_limits/1" do
    test "limit is not exceeded" do
      Enum.each(1..100, fn _i ->
        assert UsageLimiter.check_limits(%Context{
                 project_id: Ecto.UUID.generate()
               }) == :ok
      end)
    end
  end

  describe "limit_action/2" do
    test "limit is not exceeded" do
      Enum.each(1..100, fn _i ->
        assert UsageLimiter.limit_action(
                 %Action{type: :new_run},
                 %Context{project_id: Ecto.UUID.generate()}
               ) == :ok

        assert UsageLimiter.limit_action(
                 %Action{type: :new_workflow},
                 %Context{project_id: Ecto.UUID.generate()}
               ) == :ok
      end)
    end
  end
end
