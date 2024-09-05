defmodule Lightning.AiAssistant.LimiterTest do
  use ExUnit.Case, async: true

  import Mox

  alias Lightning.AiAssistant.Limiter

  setup :verify_on_exit!

  describe "validate_quota" do
    test "return ok when limit is not reached" do
      project_id = Ecto.UUID.generate()

      stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn %{
                                                                      type:
                                                                        :ai_query
                                                                    },
                                                                    %{
                                                                      project_id:
                                                                        ^project_id
                                                                    } ->
        :ok
      end)

      assert :ok == Limiter.validate_quota(project_id)
    end

    test "return limiter error when limit is reached" do
      limiter_error =
        {:error, :too_many_queries,
         %Lightning.Extensions.Message{text: "Too many queries"}}

      project_id = Ecto.UUID.generate()

      stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn %{
                                                                      type:
                                                                        :ai_query
                                                                    },
                                                                    %{
                                                                      project_id:
                                                                        ^project_id
                                                                    } ->
        limiter_error
      end)

      assert limiter_error == Limiter.validate_quota(project_id)
    end
  end
end
