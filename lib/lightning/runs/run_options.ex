defmodule Lightning.Runs.RunOptions do
  @moduledoc """
  Options that are passed to the worker to control configurable limits and
  behaviors during run execution and reporting.
  """
  use Lightning.Schema

  @type t :: %__MODULE__{
          save_dataclips: boolean(),
          run_timeout_ms: integer()
        }

  @type keyword_list :: [
          save_dataclips: boolean(),
          run_timeout_ms: integer()
        ]

  @primary_key false
  embedded_schema do
    field :save_dataclips, :boolean, default: true
    field :run_timeout_ms, :integer, default: 60_000
  end

  defimpl Jason.Encoder, for: __MODULE__ do
    def encode(value, opts) do
      Jason.Encode.map(Map.take(value, [:save_dataclips, :run_timeout_ms]), opts)
    end
  end
end
