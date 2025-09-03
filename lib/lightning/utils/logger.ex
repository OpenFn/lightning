defmodule Lightning.Utils.Logger do
  @moduledoc """
  Utility functions for working with the logger.
  """

  defmacro __using__(opts \\ []) do
    quote do
      opts = unquote(opts)
      require Logger

      @mod __MODULE__ |> Module.split() |> List.last()

      @mod_color unquote(Keyword.get(opts, :color, []) |> List.wrap())

      def info(message) do
        Logger.info(
          unquote(__MODULE__).format_message(@mod_color, @mod, message)
        )
      end

      def debug(message) do
        Logger.debug(
          unquote(__MODULE__).format_message(@mod_color, @mod, [
            IO.ANSI.color(2, 2, 2),
            message
          ])
        )
      end

      def warning(message) do
        Logger.warning(
          unquote(__MODULE__).format_message(@mod_color, @mod, [:yellow, message])
        )
      end

      def error(message) do
        Logger.error(
          unquote(__MODULE__).format_message(@mod_color, @mod, [:red, message])
        )
      end
    end
  end

  def format_message(mod_color, mod, message) do
    [mod_color, [mod, :reset, " "], List.wrap(message)]
    |> List.flatten()
    |> IO.ANSI.format()
  end
end
