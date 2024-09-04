defmodule Lightning.Extensions.UsageLimiterTest do
  use ExUnit.Case, async: true

  alias Ecto.Multi

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

  describe "increment_ai_queries/2" do
    test "returns the same multi" do
      session = %Lightning.AiAssistant.ChatSession{job_id: Lightning.Factories.build(:job)}

      multi = Multi.new() |> Multi.put(:session, session)

      assert Multi.merge(fn %{session: session} -> UsageLimiter.increment_ai_queries(session) == multi
    end
  end
end
