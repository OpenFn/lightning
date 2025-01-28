defmodule Lightning.Extensions.UsageLimiting do
  @moduledoc """
  Rate limiting for Lightning workloads that depends on Runtime.
  """
  @type error_reason ::
          :too_many_runs
          | :runs_hard_limit
          | :exceeds_limit
          | :unknown_project
  @type message :: Lightning.Extensions.Message.t()
  @type error :: {:error, error_reason(), message()}

  defmodule Action do
    @moduledoc false
    @type t :: %__MODULE__{
            type:
              :activate_workflow
              | :ai_usage
              | :alert_failure
              | :collection_create
              | :collection_put
              | :github_sync
              | :new_run
              | :new_user
              | :require_mfa,
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

  @doc """
  Checks the usage limits for a given project and user context, returning an error
  message if the limits are exceeded.

  Requires a `Context` struct containing the `project_id` and `user_id`.

  ## Returns

    - `{:ok}` if the limits are within bounds.
    - `{:error, reason, message}` if the limits are exceeded.
  """
  @callback check_limits(context :: Context.t()) ::
              :ok | error()

  @doc """
  Limits specific actions based on an `Action` and `Context`.

  ## Returns

    - `:ok` if the action is allowed.
    - `{:error, reason, message}` if the action is not allowed.
  """
  @callback limit_action(action :: Action.t(), context :: Context.t()) ::
              :ok | error()

  @doc """
  Increments the AI query count for a given chat session.

  Requires a `Lightning.AiAssistant.ChatSession` struct.

  ## Returns

    - An Ecto.Multi struct representing the transaction to increment AI queries.
  """
  @callback increment_ai_usage(Lightning.AiAssistant.ChatSession.t(), map()) ::
              Ecto.Multi.t()

  @doc """
  Returns run options based on the given project context. The run options include
  a timeout value and a flag for saving dataclips.

  Requires a `Context` struct containing the `project_id`.

  ## Returns

    - A keyword list of run options including:
      - `:run_timeout_ms`: The run timeout in milliseconds.
      - `:save_dataclips`: A boolean indicating whether to save dataclips.
  """
  @callback get_run_options(context :: Context.t()) ::
              Lightning.Runs.RunOptions.keyword_list()

  @callback get_data_retention_periods(context :: Context.t()) :: [
              pos_integer(),
              ...
            ]

  @callback get_data_retention_message(context :: Context.t()) :: message() | nil
end
