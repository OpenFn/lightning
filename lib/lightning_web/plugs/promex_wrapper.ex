defmodule LightningWeb.Plugs.PromexWrapper do
  @moduledoc """
  Ensures that the MetricsAuth plug always comes before the PromEx plug.
  """
  use Plug.Builder

  plug LightningWeb.Plugs.MetricsAuth
  plug PromEx.Plug, prom_ex_module: Lightning.PromEx
end
