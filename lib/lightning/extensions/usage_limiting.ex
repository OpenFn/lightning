defmodule Lightning.Extensions.UsageLimiting do
  @moduledoc """
  Rate limiting for Lightning workloads that depends on Runtime.
  """
  @type error_reason ::
          :too_many_runs
          | :too_many_batch_runs
          | :runs_hard_limit
          | :unknown_project
  @type message :: Lightning.Extensions.Message.t()
  @type error :: {:error, error_reason(), message()}

  defmodule Action do
    @moduledoc false
    @type t :: %__MODULE__{
            type: :new_run | :new_run_batch | :new_workflow,
            amount: pos_integer()
          }

    defstruct [:type, :amount]
  end

  defmodule Context do
    @moduledoc false

    @type t :: %Context{
            project_id: Ecto.UUID.t()
          }

    defstruct [:project_id, :user_id]
  end

  @callback check_limits(context :: Context.t()) ::
              :ok | error()

  @callback limit_action(action :: Action.t(), context :: Context.t()) ::
              :ok | error()
end
