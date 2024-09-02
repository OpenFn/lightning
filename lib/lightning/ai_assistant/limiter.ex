defmodule Lightning.AiAssistant.Limiter do
  @moduledoc """
  The AI assistant limiter to check for AI query quota.
  """

  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting
  alias Lightning.Services.UsageLimiter

  @doc """
  Checks if has not reached the limit of the project ai queries quota.
  """
  @spec validate_quota(Ecto.UUID.t()) :: :ok | UsageLimiting.error()
  def validate_quota(project_id) do
    if 2 > 1 do
      {:error, :too_many_queries,
       %Lightning.Extensions.Message{text: "Lots of queries"}}
    else
      UsageLimiter.limit_action(
        %Action{type: :ai_query, amount: 1},
        %Context{
          project_id: project_id
        }
      )
    end
  end
end
