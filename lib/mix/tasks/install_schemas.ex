defmodule Mix.Tasks.Lightning.InstallSchemas do
  @shortdoc "Install the credential json schemas"

  @moduledoc """
  Install the credential json schemas
  """

  use Mix.Task
  use HTTPoison.Base

  @schemas_path "priv/schemas/"

  def run(args) do

    IO.inspect(args)
    HTTPoison.start()

    File.mkdir_p(@schemas_path)
    |> case do
      {:error, reason} ->
        raise "Couldn't create the schemas directory: #{@schemas_path}, got :#{reason}."
      _ ->
        nil
    end

    fetch_schemas()
  end

  defp get_adaptor_name(package_name) do
    ~r/(@?[\/\d\n\w-]+)(?:@([\d\.\w-]+))?$/
    |> Regex.run(package_name)
  end

  defp write_schema(package_name, data) when is_binary(package_name) do
    package_name
    |> get_adaptor_name()
    |> case do
      [_, name] ->
        file =
          File.open!(
            @schemas_path <>
              String.replace(name, "@openfn/language-", "") <> ".json",
            [:write]
          )

        IO.binwrite(file, data)
        File.close(file)

      _ ->
        {:error, :bad_format}
    end
  end

  defp persist_schema(package_name) do
    get(
      "https://cdn.jsdelivr.net/npm/#{package_name}/configuration-schema.json",
      [],
      hackney: [pool: :default],
      recv_timeout: 15_000
    )
    |> case do
      {:error, %HTTPoison.Error{}} ->
        Mix.shell().error("Unable to fetch #{package_name} schema")
        nil

      {:ok, resp} ->
        body = Map.get(resp, :body)
        write_schema(package_name, body)
    end
  end

  def fetch_schemas() do
    get("https://registry.npmjs.org/-/user/openfn/package", [])
    |> case do
      {:error, %HTTPoison.Error{reason: :nxdomain, id: nil}} ->
        Mix.shell().error("Unable to connect to NPM; no adaptors fetched.")
        []

      {:ok, resp} ->
        Map.get(resp, :body)
        |> Jason.decode!()
        |> Enum.map(fn {name, _} -> name end)
        |> Enum.filter(fn name ->
          Regex.match?(~r/@openfn\/language-\w+/, name)
        end)
        |> Task.async_stream(
          &persist_schema/1,
          ordered: false,
          max_concurrency: 5,
          timeout: 30_000
        )
        |> Stream.map(fn {:ok, detail} -> detail end)
        |> Enum.to_list()

        Mix.shell().info("Schemas installation has finished")

    end
  end
end
