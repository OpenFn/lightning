defmodule Lightning.Extensions.UsageLimiting do
  @moduledoc """
  Rate limiting for Lightning workloads that depends on Runtime.
  """
  @type action_error :: :too_many_actions | :unknown
  @type limit_error :: :too_many_runs | :too_many_workorders | :unknown

  @type message :: %{
          position: atom(),
          text: String.t() | nil,
          function: fun(),
          attrs: Keyword.t()
        }

  defmodule Action do
    @moduledoc false
    @type t :: %__MODULE__{
            type: :new_run | :new_workflow | :new_workorder
          }

    defstruct [:type]
  end

  defmodule Context do
    @moduledoc false

    @type t :: %Context{
            project_id: Ecto.UUID.t()
          }

    defstruct [:project_id, :user_id]
  end

  @callback check_limits(context :: Context.t()) ::
              :ok | {:error, limit_error(), message()}

  @callback limit_action(action :: Action.t(), context :: Context.t()) ::
              :ok | {:error, action_error(), message()}
end
