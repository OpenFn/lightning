defmodule Mix.Tasks.Lightning.Gen.AppMap do
  @shortdoc "Generate priv/app_map.json, the catalog of user-facing pages"

  @moduledoc """
  Writes `LightningWeb.AppMap.to_json/0` — the machine-readable catalog of
  every user-facing page in the app — to a pretty-printed JSON file, for
  feeding to the AI assistant.

  The map itself is authored and verified in `LightningWeb.AppMap`: routes
  come from router introspection and every page carries a human-written
  description. This task only serialises it.

  ## Usage

      mix lightning.gen.app_map
      mix lightning.gen.app_map --path app_map.json

  Without `--path`, writes to `app_map.json` in this instance's `priv`
  directory.
  """

  use Mix.Task

  @requirements ["compile"]

  @impl Mix.Task
  def run(args) do
    pages = LightningWeb.AppMap.to_json()

    path = parse_path(args)
    File.write!(path, [Jason.encode_to_iodata!(pages, pretty: true), "\n"])

    Mix.shell().info("Wrote #{length(pages)} pages to #{path}")
  end

  defp parse_path(args) do
    default_path = Path.join(:code.priv_dir(:lightning), "app_map.json")

    {opts, _argv, _errors} = OptionParser.parse(args, strict: [path: :string])
    opts[:path] || default_path
  end
end
