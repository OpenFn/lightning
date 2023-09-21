defmodule Mix.Tasks.Lightning.InstallAdaptorIcons do
  @moduledoc """
  Installs the adaptor icons
  """
  use Mix.Task
  use Tesla, except: [:post, :put, :delete]

  plug Tesla.Middleware.FollowRedirects

  @adaptors_tar_url "https://github.com/OpenFn/adaptors/archive/refs/heads/main.tar.gz"

  @target_dir Application.compile_env(:lightning, :adaptor_icons_path)

  @impl true
  def run(_) do
    Application.ensure_all_started(:hackney)

    File.mkdir_p(@target_dir)
    |> case do
      {:error, reason} ->
        raise "Couldn't create the adaptors images directory: #{@target_dir}, got :#{reason}."

      :ok ->
        :ok
    end

    working_dir = tmp_dir!()
    tar = fetch_body!(@adaptors_tar_url)

    case :erl_tar.extract({:binary, tar}, [
           :compressed,
           cwd: to_charlist(working_dir)
         ]) do
      :ok -> :ok
      other -> raise "couldn't unpack archive: #{inspect(other)}"
    end

    adaptor_icons = save_icons(working_dir)
    manifest_path = Path.join(@target_dir, "adaptor_icons.json")
    :ok = File.write(manifest_path, Jason.encode!(adaptor_icons))

    Mix.shell().info(
      "Adaptor icons installed successfully. Manifest saved at: #{manifest_path}"
    )
  end

  defp fetch_body!(url) do
    response = get!(url)
    response.body
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

  defp save_icons(working_dir) do
    working_dir
    |> list_icons()
    |> Enum.map(fn icon_path ->
      [icon_name, "assets", adapter_name | _rest] =
        Path.split(icon_path) |> Enum.reverse()

      destination_name = adapter_name <> "-" <> icon_name
      destination_path = Path.join(@target_dir, destination_name)
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
