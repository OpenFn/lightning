defmodule Lightning.Runs.RunOptions do
  @moduledoc """
  Options that are passed to the worker to control configurable limits and
  behaviors during run execution and reporting.
  """
  use Ecto.Schema

  embedded_schema do
    field :burn_input_after_reading, :boolean, default: false
    field :output_dataclips, :boolean, default: true
    field :run_timeout_ms, :integer, default: 10_000
  end
end
