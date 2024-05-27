defmodule Lightning.Extensions.UsageLimiter do
  @moduledoc """
  Runtime limiting stub for Lightning.
  """
  @behaviour Lightning.Extensions.UsageLimiting

  @impl true
  def check_limits(_context), do: :ok

  @impl true
  def limit_action(_action, _context), do: :ok

  @impl true
  def get_run_options(context),
    do: [
      save_dataclips: Lightning.Projects.save_dataclips?(context.project_id),
      run_timeout_ms: Lightning.Config.default_max_run_duration() * 1000
    ]
end
