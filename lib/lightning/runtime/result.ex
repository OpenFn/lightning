defmodule Lightning.Runtime.Result do
  @moduledoc """
  Data structure used to represent the result of a Run executed by
  `Lightning.Runtime.ChildProcess`.
  """
  @type t :: %__MODULE__{
          exit_reason: atom(),
          log: list(String.t()),
          final_state_path: String.t()
        }

  defstruct [:exit_reason, :log, :final_state_path]

  def new(fields \\ []) do
    struct!(__MODULE__, fields)
  end
end
