defmodule Lightning.RedactedMap do
  @moduledoc false

  @type t :: %__MODULE__{value: map()}
  defstruct [:value]

  defimpl Jason.Encoder, for: Lightning.RedactedMap do
    def encode(%{value: map}, opts) do
      Jason.Encode.map(map, opts)
    end
  end

  defimpl Inspect, for: Lightning.RedactedMap do
    def inspect(_map, _opts) do
      "[REDACTED]"
    end
  end

  def new(value) do
    struct(Lightning.RedactedMap, value: value)
  end
end
