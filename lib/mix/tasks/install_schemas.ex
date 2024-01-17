defmodule Mix.Tasks.Lightning.InstallSchemas do
  @shortdoc "Install the credential json schemas"

  @moduledoc """
  Install the credential json schemas
  Use --exclude language-package1, language-package2 to exclude specific packages
  """

  use Mix.Task
  use HTTPoison.Base
  require Logger

  @default_excluded_adaptors [
    "language-common",
    "language-devtools",
    "language-divoc"
  ]

  @spec run(any) :: any
  def run(args) do
    HTTPoison.start()

    dir = schemas_path()

    init_schema_dir(dir)

    result =
      args
      |> parse_excluded()
      |> fetch_schemas(&persist_schema(dir, &1))
      |> Enum.to_list()

    Mix.shell().info(
      "Schemas installation has finished. #{length(result)} installed"
    )
  end

  def parse_excluded(args) do
    args
    |> case do
      ["--exclude" | adaptor_names] when adaptor_names != [] ->
        (adaptor_names ++ @default_excluded_adaptors) |> Enum.uniq()

      _ ->
        @default_excluded_adaptors
    end
  end

  defp schemas_path do
    Application.get_env(:lightning, :schemas_path)
  end

  defp init_schema_dir(dir) do
    if is_nil(dir), do: raise("Schema directory not provided.")
    File.rm_rf(dir)

    File.mkdir_p(dir)
    |> case do
      {:error, reason} ->
        raise "Couldn't create the schemas directory: #{dir}, got :#{reason}."

      _ ->
        nil
    end
  end

  def write_schema(dir, package_name, data) when is_binary(package_name) do
    path =
      Path.join([
        dir,
        String.replace(package_name, "@openfn/language-", "") <> ".json"
      ])

    file = File.open!(path, [:write])

    IO.binwrite(file, data)
    File.close(file)
  end

  def persist_schema(dir, package_name) do
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
        write_schema(dir, package_name, body)

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.warning(
          "Unable to fetch #{package_name} configuration schema. status=#{status_code}"
        )
    end
  end

  def fetch_schemas(excluded \\ [], fun) do
    get("https://registry.npmjs.org/-/user/openfn/package", [],
      hackney: [pool: :default],
      recv_timeout: 15_000
    )
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
        |> Task.async_stream(fun,
          ordered: false,
          max_concurrency: 5,
          timeout: 30_000
        )
        |> Stream.map(fn {:ok, detail} -> detail end)

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        raise "Unable to access openfn user packages. status=#{status_code}"
    end
  end
end
