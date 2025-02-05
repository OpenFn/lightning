defmodule LightningWeb.PlugManager do
  @moduledoc """
  Helper module for setting up plugs in a Phoenix endpoint or router.

  This module provides a macro to simplify the setup of multiple plugs
  configured through application environment variables.
  """

  @doc """
  Sets up multiple plugs using Replug.

  Takes a list of plug configurations in the format of `{PlugModule, opts}` where:
  - `PlugModule` is the module implementing the plug
  - `opts` can be a keyword list of options or a tuple containing a module and function
    to be called for dynamic configuration

  ## Example

      @pre_session_plugs Application.compile_env(:my_app, :pre_session_plugs, [])
      setup(@pre_session_plugs)

  The above will set up all configured plugs using Replug with their respective options.
  """
  defmacro setup(plugs) do
    quote do
      for {plug, opts} <- unquote(plugs) do
        plug Replug, plug: plug, opts: opts
      end
    end
  end
end
