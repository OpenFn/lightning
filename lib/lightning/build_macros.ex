defmodule Lightning.BuildMacros do
  @moduledoc """
  Macros for building Lightning.
  """

  defmacro __using__(_opts) do
    quote do
      require Lightning.BuildMacros
      import Lightning.BuildMacros
    end
  end

  @doc """
  Conditionally evaluates the block if the current environment is in the
  given list of environments.

  ## Examples

      do_in(:dev) do
        IO.puts("This will only be printed in the dev environment")
      end

      do_in([:dev, :test]) do
        IO.puts("This will only be printed in the dev and test environments")
      end
  """
  @spec do_in([atom()] | atom(), do: Macro.t()) :: Macro.t()
  defmacro do_in(envs, do: block) do
    envs = List.wrap(envs)

    if Mix.env() in envs do
      quote do
        unquote(block)
      end
    end
  end
end
