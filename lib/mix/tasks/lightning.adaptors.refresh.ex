defmodule Mix.Tasks.Lightning.Adaptors.Refresh do
  @shortdoc "On-demand adaptor metadata refresh"
  @moduledoc """
  Trigger an adaptor catalogue refresh from the command line.

  ## Usage

      mix lightning.adaptors.refresh
      mix lightning.adaptors.refresh --name @openfn/language-http

  Without `--name`, starts a refresh cycle (or joins one already running)
  and waits for it to finish. With `--name`, refetches that one adaptor.

  ## Exit codes

    * `0` - success
    * `1` - package name not found
    * `2` - any other error, including a listing that returned no adaptors
      or a refresh that took longer than 10 minutes
  """

  use Mix.Task

  @await_timeout :timer.minutes(10)

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _args} = OptionParser.parse!(argv, strict: [name: :string])

    case opts[:name] do
      nil -> refresh_all()
      pkg -> refresh_one(pkg)
    end
  end

  defp refresh_all do
    Mix.shell().info("Refreshing adaptors (waiting up to 10 minutes)...")
    started = System.monotonic_time(:millisecond)

    case Lightning.Adaptors.refresh(Lightning.Adaptors,
           await: true,
           timeout: @await_timeout
         ) do
      {:ok, %{listed: 0}} ->
        Mix.shell().error("Refresh completed but the source listed no adaptors.")
        exit({:shutdown, 2})

      {:ok, counts} ->
        duration_s = div(System.monotonic_time(:millisecond) - started, 1000)

        Mix.shell().info(
          "Refresh complete: listed #{counts.listed}, " <>
            "fetched #{counts.fetched}, errors #{counts.errors} " <>
            "(#{duration_s}s)."
        )

      {:error, :timeout} ->
        Mix.shell().error("Refresh did not complete within 10 minutes.")
        exit({:shutdown, 2})

      {:error, reason} ->
        Mix.shell().error("Refresh failed: #{inspect(reason)}")
        exit({:shutdown, 2})
    end
  end

  defp refresh_one(pkg) do
    case Lightning.Adaptors.refresh_package(pkg) do
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
