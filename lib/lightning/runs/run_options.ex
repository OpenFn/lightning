defmodule Lightning.Runs.RunOptions do
  @moduledoc """
  Options that are passed to the worker to control configurable limits and
  behaviors during run execution and reporting.
  """
  use Lightning.Schema

  @type t :: %__MODULE__{
          save_dataclips: boolean(),
          run_timeout_ms: integer(),
          run_memory_limit_mb: integer() | nil
        }

  @type keyword_list :: [
          save_dataclips: boolean(),
          run_timeout_ms: integer(),
          run_memory_limit_mb: integer() | nil
        ]

  @primary_key false
  embedded_schema do
    field :save_dataclips, :boolean, default: true
    field :run_timeout_ms, :integer, default: 60_000
    field :run_memory_limit_mb, :integer
    field :enable_job_logs, :boolean
  end

  def new(opts \\ %{}) do
    %__MODULE__{}
    |> cast(opts, [:save_dataclips, :run_timeout_ms])
  end

  defimpl Jason.Encoder, for: __MODULE__ do
    def encode(value, opts) do
      value
      |> Map.take([
        :save_dataclips,
        :run_timeout_ms,
        :run_memory_limit_mb,
        :enable_job_logs
      ])
      |> Map.reject(fn {_key, val} -> is_nil(val) end)
      |> Jason.Encode.map(opts)
    end
  end
end
