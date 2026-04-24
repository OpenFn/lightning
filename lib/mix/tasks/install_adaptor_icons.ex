defmodule Mix.Tasks.Lightning.InstallAdaptorIcons do
  @moduledoc """
  Installs the adaptor icons.

  Refreshes the icon manifest from the adaptor registry and optionally
  prefetches icon PNGs from GitHub into the database cache.

  All core logic lives in `Lightning.AdaptorIcons`; this task only
  handles application startup and CLI output.
  """

  use Mix.Task

  @impl true
  def run(_) do
    Mix.Task.run("app.start")

    case Lightning.AdaptorIcons.refresh() do
      {:ok, manifest} ->
        Mix.shell().info(
          "Adaptor icons refreshed successfully. " <>
            "#{map_size(manifest)} adaptors in manifest."
        )

      {:error, reason} ->
        Mix.raise("Adaptor icons refresh failed: #{inspect(reason)}")
    end
  end
end
