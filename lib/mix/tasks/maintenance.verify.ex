defmodule Mix.Tasks.Lightning.Maintenance.Verify do
  @shortdoc "End-to-end smoke test for the Maintenance page actions"

  @moduledoc """
  Runs `Lightning.MaintenanceVerify.run/0` as a standalone mix task.

  This variant starts the full application, so stop any running
  `iex -S mix phx.server` first (otherwise the Node worker port will
  collide).

  If you already have a dev server running, prefer calling the
  verifier directly from your IEx session:

      iex> Lightning.MaintenanceVerify.run()

  Requires real database and network access (NPM, jsDelivr, GitHub).
  Exits 1 on any failure.
  """

  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    case Lightning.MaintenanceVerify.run() do
      :ok -> :ok
      :error -> exit({:shutdown, 1})
    end
  end
end
