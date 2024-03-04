defmodule Lightning.Extensions.Message do
  @moduledoc """
  Message for the limiters to communicate with the client.
  """
  @type t :: %__MODULE__{
          position: atom() | nil,
          text: String.t() | nil,
          function: fun() | nil,
          attrs: map() | nil
        }

  defstruct [:attrs, :function, :position, :text]
end
