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
    UsageLimiter.limit_action(%Action{type: :ai_query}, %Context{
        project_id: project_id
      }
    )
  end
end
