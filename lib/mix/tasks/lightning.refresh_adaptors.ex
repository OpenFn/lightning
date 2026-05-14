defmodule Mix.Tasks.Lightning.RefreshAdaptors do
  @shortdoc "On-demand adaptor metadata refresh"
  @moduledoc """
  Trigger an immediate adaptor refresh from the command line.

  Use cases:

    * Dev re-scan — force a re-scan after adding local adaptors
    * Ops force-pull — pull latest metadata without waiting for the scheduler tick
    * Debug in terminal — confirm the leader node holds the HighlanderPG lease

  ## Usage

      mix lightning.refresh_adaptors
      mix lightning.refresh_adaptors --name @openfn/language-http

  The first form calls `Lightning.Adaptors.refresh_now/0`, refreshing all
  adaptors. The second form calls `Lightning.Adaptors.refresh_package/1`
  to force a single-adaptor refresh, bypassing the ledger diff.

  Both forms block until completion. The active strategy and source are
  resolved by the running supervisor — strategy is never set on the CLI.

  ## Exit codes

    * `0` — success
    * `1` — not the HighlanderPG leader; run from the leader node or wait for the next tick
    * `2` — package name not found (possible typo)
    * `3` — other error
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _args} = OptionParser.parse!(argv, strict: [name: :string])

    result =
      case opts[:name] do
        nil -> Lightning.Adaptors.refresh_now()
        pkg -> Lightning.Adaptors.refresh_package(pkg)
      end

    case result do
      :ok ->
        Mix.shell().info("Adaptors refreshed successfully.")

      {:error, :not_leader} ->
        Mix.shell().error(
          "Not the leader node. Run from the node that holds the HighlanderPG lease, or wait."
        )

        exit({:shutdown, 1})

      {:error, :not_found} ->
        Mix.shell().error("Package not found. Check the name and try again.")
        exit({:shutdown, 2})

      {:error, reason} ->
        Mix.shell().error("Refresh failed: #{inspect(reason)}")
        exit({:shutdown, 3})
    end
  end
end
