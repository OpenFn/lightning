defmodule Lightning.Extensions.UsageLimiting do
  @moduledoc """
  Rate limiting for Lightning workloads that depends on Runtime.
  """
  @type error_reason ::
          :too_many_runs
          | :too_many_queries
          | :runs_hard_limit
          | :unknown_project
  @type message :: Lightning.Extensions.Message.t()
  @type error :: {:error, error_reason(), message()}

  defmodule Action do
    @moduledoc false
    @type t :: %__MODULE__{
            type:
              :new_run
              | :activate_workflow
              | :ai_query
              | :alert_failure
              | :github_sync
              | :new_user,
            amount: pos_integer()
          }

    defstruct type: nil, amount: 1
  end

  defmodule Context do
    @moduledoc false

    @type t :: %Context{
            project_id: Ecto.UUID.t(),
            user_id: Ecto.UUID.t()
          }

    defstruct [:project_id, :user_id]
  end

  @callback check_limits(context :: Context.t()) ::
              :ok | error()

  @callback limit_action(action :: Action.t(), context :: Context.t()) ::
              :ok | error()

  @callback get_run_options(context :: Context.t()) ::
              Lightning.Runs.RunOptions.keyword_list()
end
