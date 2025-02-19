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

  @callback render(assigns :: Socket.assigns()) :: Phoenix.LiveView.Rendered.t()

  defmacro __using__(_opts \\ []) do
    quote do
      use Phoenix.Component
      import Phoenix.Component
      import Phoenix.HTML

      require Logger
    end
  end
end
