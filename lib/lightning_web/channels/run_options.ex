defmodule LightningWeb.RunOptions do
  @moduledoc false
  @type t :: %__MODULE__{}
  @derive Jason.Encoder
  defstruct [:output_dataclips]
end
