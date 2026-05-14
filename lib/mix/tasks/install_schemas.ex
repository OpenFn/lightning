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

  # Descending on purpose: the first attempt is generous to let jsdelivr warm
  # a cold cache for packages it hasn't served recently. Follow-up attempts
  # are shorter because we expect a now-warm hit and want to fail fast if not.
  @recv_timeouts [30_000, 15_000, 5_000]

  # hackney error reasons that we treat as transient and worth retrying.
  # Anything else (e.g. :nxdomain, :econnrefused) is logged with its reason
  # and skipped immediately rather than retried.
  @retriable_reasons [:timeout, :closed, :connect_timeout, :checkout_timeout]

  # Outer Task.async_stream timeout. Must comfortably exceed the sum of
  # @recv_timeouts (50s) plus connect/DNS/body overhead.
  @async_stream_timeout 75_000

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

      {:error, %HTTPoison.Error{reason: reason}}
      when reason in @retriable_reasons and rest != [] ->
        [next_timeout | _] = rest

        Logger.warning(
          "Transient error fetching #{package_name} (#{inspect(reason)}); " <>
            "retrying with recv_timeout=#{next_timeout}ms"
        )

        attempt_persist_schema(dir, package_name, rest)

      {:error, %HTTPoison.Error{reason: reason}} ->
        attempts_used = length(@recv_timeouts) - length(rest)

        Logger.warning(
          "Skipping #{package_name}: #{inspect(reason)} after " <>
            "#{attempts_used} attempt(s)"
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

        names =
          body
          |> Jason.decode!()
          |> Enum.map(fn {name, _} -> name end)
          |> Enum.filter(fn name ->
            Regex.match?(~r/@openfn\/language-\w+/, name)
          end)
          |> Enum.reject(fn name -> name in excluded end)

        # Wrap fun so a worker crash (raise/exit) becomes a normal {:skipped,
        # _, _} result instead of taking the caller down via the task link.
        # ordered: true (the default) lets us zip results against `names` so
        # the on_timeout: :kill_task path can also recover the package name.
        safe_fun = fn name ->
          try do
            fun.(name)
          catch
            kind, reason ->
              Logger.warning(
                "Schema fetch worker for #{name} crashed: " <>
                  "#{inspect({kind, reason})}"
              )

              {:skipped, name, {kind, reason}}
          end
        end

        names
        |> Task.async_stream(safe_fun,
          max_concurrency: 5,
          timeout: @async_stream_timeout,
          on_timeout: :kill_task
        )
        |> Stream.zip(names)
        |> Stream.map(fn
          {{:ok, result}, _name} ->
            result

          {{:exit, reason}, name} ->
            Logger.warning(
              "Schema fetch task for #{name} killed: #{inspect(reason)}"
            )

            {:skipped, name, reason}
        end)

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        raise "Unable to access openfn user packages. status=#{status_code}"
    end
  end
end
