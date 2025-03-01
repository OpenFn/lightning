defmodule React.Component do
  @moduledoc """
  Defines a stateless component.

  ## Example

      defmodule Button do
        use React.Component

        jsx "react/Button.tsx"
      end

  > **Note**: Stateless components cannot handle Phoenix LiveView events.
  If you need to handle them, please use a `React.LiveComponent` instead (not
  currently implemented).
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import React
    end
  end
end
