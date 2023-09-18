defmodule Mix.Tasks.Lightning.InstallAdaptorIcons do
  use Mix.Task
  @requirements ["app.start"]

  @adaptors_tar_url "https://github.com/OpenFn/adaptors/archive/refs/heads/main.tar.gz"

  @target_dir Path.expand("../../../priv/static/assets/images/adaptors", __DIR__)

  def run(_) do
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

    for icon_path <- list_icons(working_dir) do
      [icon_name, "assets", adapter_name | _rest] =
        Path.split(icon_path) |> Enum.reverse()

      destination_name = adapter_name <> "-" <> icon_name
      destination_path = Path.join(@target_dir, destination_name)
      File.cp!(icon_path, destination_path)
    end

    :ok
  end

  defp fetch_body!(url) do
    client = Tesla.client([Tesla.Middleware.FollowRedirects])
    response = Tesla.get!(client, url)
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
end
