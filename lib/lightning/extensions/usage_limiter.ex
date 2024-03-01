defmodule Lightning.Extensions.UsageLimiter do
  @moduledoc """
  Runtime limiting stub for Lightning.
  """
  @behaviour Lightning.Extensions.UsageLimiting

  alias Lightning.Extensions.Message

  @impl true
  def check_limits(_context), do: :ok

  @impl true
  def limit_action(_action, _context),
    do: {:error, :too_many, %Message{text: "Too many requests"}}
end
