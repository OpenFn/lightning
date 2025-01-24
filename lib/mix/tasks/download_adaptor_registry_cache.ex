defmodule Mix.Tasks.Lightning.DownloadAdaptorRegistryCache do
  @shortdoc "Downloads the adaptor registry json cache"

  @moduledoc """
  Downloads the adaptor registry json cache
  Use --path to specify the location
  """

  use Mix.Task

  alias Lightning.AdaptorRegistry

  def run(args) do
    Application.ensure_started(:telemetry)
    Finch.start_link(name: Lightning.Finch)

    case AdaptorRegistry.fetch() do
      [] ->
        Mix.shell().error(
          "No adaptors found! Check that you have internet connection"
        )

      adaptors ->
        path = parse_path(args)
        cache_file = File.open!(path, [:write])
        IO.binwrite(cache_file, Jason.encode_to_iodata!(adaptors))
        File.close(cache_file)

        Mix.shell().info(
          "AdaptorRegistry downloaded successfully. File stored at: #{path}"
        )
    end
  end

  defp parse_path(args) do
    default_path =
      Path.join([
        :code.priv_dir(:lightning),
        "adaptor_registry_cache.json"
      ])

    {opts, _argv, _errors} = OptionParser.parse(args, strict: [path: :string])
    opts[:path] || default_path
  end
end
