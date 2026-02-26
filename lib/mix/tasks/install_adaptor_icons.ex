defmodule Mix.Tasks.Lightning.InstallAdaptorIcons do
  @moduledoc """
  Installs the adaptor icons.

  All core logic lives in `Lightning.AdaptorIcons`; this task only
  handles application startup and CLI output.
  """

  use Mix.Task

  @impl true
  def run(_) do
    Application.ensure_all_started(:telemetry)
    Finch.start_link(name: Lightning.Finch)

    case Lightning.AdaptorIcons.refresh() do
      {:ok, _manifest} ->
        target_dir = Application.fetch_env!(:lightning, :adaptor_icons_path)
        manifest_path = Path.join(target_dir, "adaptor_icons.json")

        Mix.shell().info(
          "Adaptor icons installed successfully. Manifest saved at: #{manifest_path}"
        )

      {:error, reason} ->
        Mix.raise("Adaptor icons installation failed: #{inspect(reason)}")
    end
  end
end
