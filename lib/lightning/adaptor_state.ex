defmodule Lightning.AdaptorState do
  @moduledoc false

  @type t :: %__MODULE__{configuration: map()}
  @derive Jason.Encoder
  defstruct [:configuration]

  defimpl Inspect, for: Lightning.AdaptorState do
    def inspect(%{configuration: _config}, _opts) do
      Kernel.inspect(%{"configuration" => "[FILTERED]"})
    end
  end

  def new(config) do
    struct(Lightning.AdaptorState, configuration: config)
  end
end
