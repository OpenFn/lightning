defmodule Lightning.Demo do
  @moduledoc """
  Demo encapsulates logic for setting up a demonstration site.
  """

  alias Lightning.SetupUtils

  @doc """
  Deletes everything in the database including the superuser and creates a set
  of publicly available users for a demo site via a command that can be run on
  Kubernetes-deployed systems.
  """
  def reset_demo do
    if Application.get_env(:lightning, :is_resettable_demo) do
      # The demo's log lines are timestamped in a time zone, and the minimum
      # setup doesn't start the time zone database, so a release's
      # `eval "Lightning.Demo.reset_demo()"` would crash without it.
      {:ok, _apps} = Application.ensure_all_started(:tzdata)

      {:ok, _, _} =
        Lightning.Setup.with_minimum_setup(fn ->
          SetupUtils.tear_down(destroy_super: true)
          SetupUtils.setup_demo(create_super: true)
        end)
    else
      IO.puts("I'm sorry, Dave. I'm afraid I can't do that.")
    end
  end
end
