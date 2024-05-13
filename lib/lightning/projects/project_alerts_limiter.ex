defmodule Lightning.Projects.ProjectAlertsLimiter do
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
end
