defmodule Lightning.Config do
  @moduledoc """
  Centralised runtime configuration for Lightning.
  """

  def attempts_adaptor() do
    Application.get_env(
      :lightning,
      :attempts_module,
      Lightning.Attempts.Pipeline
    )
  end
end
