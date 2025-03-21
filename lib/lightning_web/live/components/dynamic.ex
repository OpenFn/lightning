defmodule LightningWeb.DynamicComponent do
  @moduledoc """
  Provides a type to be used in assigns to denote a dynamic component
  """
  @type t() :: %LightningWeb.DynamicComponent{function: fun(), args: map()}
  @enforce_keys [:function, :args]
  defstruct [:function, :args]

  @doc "Checks whether the given value can be rendered as a dynamic component"
  @spec is_dynamic_component?(any()) :: boolean()
  def is_dynamic_component?(val) do
    is_struct(val, __MODULE__)
  end
end
