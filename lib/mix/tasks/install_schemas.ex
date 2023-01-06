defmodule Mix.Tasks.Lightning.InstallSchemas do
  @shortdoc "Install the credential json schemas"

  @moduledoc """
  Install the credential json schemas
  Use --exclude language-package1, language-package2 to exclude specific packages
  """

  use Mix.Task
  use HTTPoison.Base

  @schemas_path "priv/schemas/"

  @spec run(any) :: any
  def run(args) do
    HTTPoison.start()

    excluded =
      case args do
        ["--exclude" | adaptor_names] when length(adaptor_names) != [] ->
          adaptor_names

        _ ->
          []
      end

    File.mkdir_p(@schemas_path)
    |> case do
      {:error, reason} ->
        raise "Couldn't create the schemas directory: #{@schemas_path}, got :#{reason}."

      _ ->
        nil
    end

    fetch_schemas(excluded)
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
      {:error, _} ->
        raise "Unable to access #{package_name}"

      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        write_schema(package_name, body)

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        raise "Unable to fetch #{package_name} configuration schema. status=#{status_code}"
    end
  end

  def fetch_schemas(excluded \\ []) do
    get("https://registry.npmjs.org/-/user/openfn/package", [])
    |> case do
      {:error, %HTTPoison.Error{}} ->
        raise "Unable to connect to NPM; no adaptors fetched."

      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        excluded = excluded |> Enum.map(&"@openfn/#{&1}")

        body
        |> Jason.decode!()
        |> Enum.map(fn {name, _} -> name end)
        |> Enum.filter(fn name ->
          Regex.match?(~r/@openfn\/language-\w+/, name)
        end)
        |> Enum.reject(fn name ->
          name in excluded
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

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        raise "Unable to access openfn user packages. status=#{status_code}"
    end
  end
end
