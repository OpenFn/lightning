defmodule Lightning.Runtime.RunSpec do
  @moduledoc """
  A struct containing all the parameters required to execute a Job.
  """
  @type t :: %__MODULE__{
          expression_path: String.t(),
          adaptors_path: String.t(),
          adaptor: String.t(),
          state_path: String.t(),
          final_state_path: String.t(),
          test_mode: boolean(),
          no_console: boolean(),
          memory_limit: nil | integer(),
          env: nil | %{binary() => binary()},
          timeout: nil | integer()
        }

  @enforce_keys [:adaptor]
  defstruct @enforce_keys ++
              [
                adaptors_path: nil,
                expression_path: nil,
                final_state_path: nil,
                memory_limit: nil,
                no_console: false,
                state_path: nil,
                test_mode: false,
                env: nil,
                timeout: nil
              ]

  def new(fields \\ []) do
    struct!(__MODULE__, fields)
  end
end
