defmodule LightningWeb.PlugInstaller do
  defmacro install_plugs(plugs) do
    quote do
      for {plug, opts} <- unquote(plugs) do
        plug Replug, plug: plug, opts: opts
      end
    end
  end
end
