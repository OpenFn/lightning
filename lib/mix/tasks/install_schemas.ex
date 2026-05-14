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

  @recv_timeouts [30_000, 15_000, 5_000]

  @spec run(any) :: any
  def run(args) do
    HTTPoison.start()

    dir = schemas_path()

    init_schema_dir(dir)

    {installed, skipped} =
      args
      |> parse_excluded()
      |> fetch_schemas(&persist_schema(dir, &1))
      |> Enum.reduce({0, 0}, fn
        {:installed, _name}, {ok, skip} -> {ok + 1, skip}
        {:skipped, _name, _reason}, {ok, skip} -> {ok, skip + 1}
      end)

    Mix.shell().info(
      "Schemas installation has finished. #{installed} installed, #{skipped} skipped."
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
    attempt_persist_schema(dir, package_name, @recv_timeouts)
  end

  defp attempt_persist_schema(dir, package_name, [timeout | rest]) do
    url =
      "https://cdn.jsdelivr.net/npm/#{package_name}/configuration-schema.json"

    case get(url, [], hackney: [pool: :default], recv_timeout: timeout) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        write_schema(dir, package_name, body)
        {:installed, package_name}

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.warning(
          "Unable to fetch #{package_name} configuration schema. status=#{status_code}"
        )

        {:skipped, package_name, {:http_status, status_code}}

      {:error, %HTTPoison.Error{reason: reason}} when rest != [] ->
        Logger.warning(
          "Transient error fetching #{package_name} (#{inspect(reason)}); " <>
            "retrying with recv_timeout=#{hd(rest)}ms"
        )

        attempt_persist_schema(dir, package_name, rest)

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warning(
          "Skipping #{package_name}: #{inspect(reason)} after #{length(@recv_timeouts)} attempts"
        )

        {:skipped, package_name, reason}
    end
  end

  def fetch_schemas(excluded \\ [], fun) do
    get("https://registry.npmjs.org/-/user/openfn/package", [],
      hackney: [pool: :default],
      recv_timeout: 15_000
    )
    |> case do
      {:error, %HTTPoison.Error{reason: reason}} ->
        raise "Unable to connect to NPM; no adaptors fetched: #{inspect(reason)}"

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
          timeout: 60_000
        )
        |> Stream.map(fn
          {:ok, result} ->
            result

          {:exit, reason} ->
            Logger.warning(
              "Schema fetch task exited unexpectedly: #{inspect(reason)}"
            )

            {:skipped, "unknown", reason}
        end)

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        raise "Unable to access openfn user packages. status=#{status_code}"
    end
  end
end
