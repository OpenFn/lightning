defmodule Mix.Tasks.Lightning.DownloadAdaptorRegistryCache do
  @shortdoc "Downloads an adaptor catalogue snapshot for offline seeding"

  @moduledoc """
  Fetches every `@openfn/language-*` adaptor from npm via
  `Lightning.Adaptors.NPM` and writes the full records to a JSON file, in
  the shape `Lightning.Adaptors.Catalogue.upsert_adaptor/1` accepts.

  The file this writes is what `mix lightning.seed_adaptors_from_file`
  reads.

  Use --path to specify the location
  """

  use Mix.Task

  alias Lightning.Adaptors.NPM
  alias Lightning.Adaptors.NPM.Registry

  def run(args) do
    Application.ensure_started(:telemetry)
    Finch.start_link(name: Lightning.Finch)

    case Registry.list_adaptors() do
      {:ok, []} ->
        Mix.shell().error(
          "No adaptors found! Check that you have internet connection"
        )

      {:ok, listing} ->
        adaptors =
          listing
          |> Task.async_stream(&fetch_full_record/1,
            max_concurrency: 10,
            timeout: 30_000
          )
          |> Stream.map(fn {:ok, record} -> record end)
          |> Enum.reject(&is_nil/1)

        path = parse_path(args)
        cache_file = File.open!(path, [:write])
        IO.binwrite(cache_file, Jason.encode_to_iodata!(adaptors))
        File.close(cache_file)

        Mix.shell().info(
          "Adaptor catalogue downloaded successfully. File stored at: #{path}"
        )

      {:error, reason} ->
        Mix.shell().error("Unable to fetch adaptor listing: #{inspect(reason)}")
    end
  end

  defp fetch_full_record(%{name: name}) do
    case NPM.fetch_adaptor(name) do
      {:ok, record} -> Map.put(record, :source, :npm)
      {:error, _reason} -> nil
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
