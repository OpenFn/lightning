defmodule Lightning.Projects.ProjectLimiter do
  @moduledoc false

  alias Lightning.Extensions.UsageLimiting
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Services.UsageLimiter

  @spec limit_failure_alert(project_id :: Ecto.UUID.t()) ::
          :ok | UsageLimiting.error()
  def limit_failure_alert(project_id) do
    UsageLimiter.limit_action(%Action{type: :alert_failure}, %Context{
      project_id: project_id
    })
  end

  @spec limit_new_sandbox(project_id :: Ecto.UUID.t()) ::
          :ok | UsageLimiting.error()
  def limit_new_sandbox(project_id) do
    UsageLimiter.limit_action(
      %Action{type: :new_sandbox, amount: 1},
      %Context{project_id: project_id}
    )
  end

  @spec request_new_user(
          project_id :: Ecto.UUID.t(),
          user_count :: non_neg_integer()
        ) :: :ok | UsageLimiting.error()
  def request_new_user(project_id, user_count) do
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

  @spec get_data_retention_periods(project_id :: Ecto.UUID.t()) :: [
          pos_integer(),
          ...
        ]
  def get_data_retention_periods(project_id) do
    UsageLimiter.get_data_retention_periods(%Context{
      project_id: project_id
    })
  end

  @spec get_data_retention_message(project_id :: Ecto.UUID.t()) ::
          Lightning.Extensions.Message.t()
  def get_data_retention_message(project_id) do
    UsageLimiter.get_data_retention_message(%Context{
      project_id: project_id
    })
  end
end
