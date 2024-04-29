defmodule Lightning.Projects.ProjectUsersLimiter do
  @moduledoc false

  alias Lightning.Extensions.UsageLimiting
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Services.UsageLimiter

  @spec request_new(
          project_id :: Ecto.UUID.t(),
          user_count :: non_neg_integer()
        ) :: :ok | UsageLimiting.error()
  def request_new(project_id, user_count) do
    UsageLimiter.limit_action(
      %Action{
        type: :new_user,
        amount: user_count
      },
      %Context{
        project_id: project_id
      }
    )
  end
end
