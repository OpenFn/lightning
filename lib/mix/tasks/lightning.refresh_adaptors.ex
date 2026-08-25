defmodule Mix.Tasks.Lightning.RefreshAdaptors do
  @shortdoc "On-demand adaptor metadata refresh"
  @moduledoc """
  Trigger an immediate adaptor refresh from the command line.

  Use cases:

    * Dev re-scan — force a re-scan after adding local adaptors
    * Ops force-pull — pull latest metadata without waiting for the scheduler tick

  ## Usage

      mix lightning.refresh_adaptors
      mix lightning.refresh_adaptors --name @openfn/language-http

  The first form calls `Lightning.Adaptors.refresh_now/0`, refreshing all
  adaptors. The second form calls `Lightning.Adaptors.refresh_package/1`
  to force a single-adaptor refresh, bypassing the ledger diff.

  Both forms block until completion. The Scheduler is wrapped in
  `HighlanderPG` and registered globally, so the call routes through
  Erlang distribution to whichever node currently holds the lease — the
  CLI can be run from any node in the cluster.

  ## Exit codes

    * `0` — success
    * `1` — package name not found (possible typo)
    * `2` — other error
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

      {:error, :not_found} ->
        Mix.shell().error("Package not found. Check the name and try again.")
        exit({:shutdown, 1})

      {:error, reason} ->
        Mix.shell().error("Refresh failed: #{inspect(reason)}")
        exit({:shutdown, 2})
    end
  end
end
