defmodule Lightning.Extensions.Message do
  @moduledoc """
  Message for the limiters to communicate with the client.

  `retry_after` is how many seconds the client should wait before trying
  again, set by a limiter that knows. The API sends `Retry-After` only when it
  is set (error-format spec §4).
  """
  @type t :: %__MODULE__{
          position: atom() | nil,
          text: String.t() | nil,
          function: fun() | nil,
          attrs: map() | nil,
          retry_after: pos_integer() | nil
        }

  defstruct [:attrs, :function, :position, :text, :retry_after]
end
