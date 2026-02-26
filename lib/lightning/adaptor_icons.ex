defmodule Lightning.AdaptorIcons do
  @moduledoc """
  Downloads and installs adaptor icons at runtime.

  Fetches a tarball of the OpenFn adaptors repository from GitHub, extracts
  icon PNGs, and writes them to the configured icons directory along with
  a JSON manifest.
  """

  require Logger

  @adaptors_tar_url "https://github.com/OpenFn/adaptors/archive/refs/heads/main.tar.gz"

  @doc """
  Fetches adaptor icons from GitHub and writes them to the icons directory.

  Returns `{:ok, manifest}` on success or `{:error, reason}` on failure.
  The manifest is a map of adaptor names to their icon paths.
  """
  @spec refresh() :: {:ok, map()} | {:error, term()}
  def refresh do
    target_dir = Application.get_env(:lightning, :adaptor_icons_path)

    with :ok <- File.mkdir_p(target_dir),
         working_dir <- tmp_dir!(),
         {:ok, body} <- fetch_tarball(),
         :ok <- extract_tarball(body, working_dir) do
      manifest = save_icons(working_dir, target_dir)

      manifest_path = Path.join(target_dir, "adaptor_icons.json")
      File.write!(manifest_path, Jason.encode!(manifest))

      File.rm_rf(working_dir)
      {:ok, manifest}
    end
  rescue
    error ->
      Logger.error("Failed to refresh adaptor icons: #{inspect(error)}")
      {:error, error}
  end

  defp fetch_tarball do
    case Tesla.get(build_client(), @adaptors_tar_url) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_client do
    Tesla.client([Tesla.Middleware.FollowRedirects])
  end

  defp extract_tarball(body, working_dir) do
    :erl_tar.extract(
      {:binary, body},
      [:compressed, cwd: to_charlist(working_dir)]
    )
  end

  defp tmp_dir! do
    tmp_dir =
      Path.join([
        System.tmp_dir!(),
        "lightning-adaptor",
        "#{System.unique_integer([:positive])}"
      ])

    {:ok, _} = File.rm_rf(tmp_dir)
    :ok = File.mkdir_p(tmp_dir)

    tmp_dir
  end

  defp list_icons(working_dir) do
    [working_dir, "**", "packages", "*", "assets", "{rectangle,square}.png"]
    |> Path.join()
    |> Path.wildcard()
  end

  defp save_icons(working_dir, target_dir) do
    working_dir
    |> list_icons()
    |> Enum.map(fn icon_path ->
      [icon_name, "assets", adapter_name | _rest] =
        Path.split(icon_path) |> Enum.reverse()

      destination_name = adapter_name <> "-" <> icon_name
      destination_path = Path.join(target_dir, destination_name)
      File.cp!(icon_path, destination_path)

      %{
        adaptor: adapter_name,
        shape: Path.rootname(icon_name),
        src: "/images/adaptors" <> "/#{destination_name}"
      }
    end)
    |> Enum.group_by(fn entry -> entry.adaptor end)
    |> Enum.into(%{}, fn {adaptor, sources} ->
      sources = Map.new(sources, fn entry -> {entry.shape, entry.src} end)
      {adaptor, sources}
    end)
  end
end
