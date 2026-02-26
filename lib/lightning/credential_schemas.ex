defmodule Lightning.CredentialSchemas do
  @moduledoc """
  Downloads and installs credential configuration schemas at runtime.

  Fetches the list of OpenFn adaptor packages from npm, then downloads
  each adaptor's configuration schema from jsDelivr CDN.
  """

  require Logger

  @default_excluded_adaptors [
    "language-common",
    "language-devtools",
    "language-divoc"
  ]

  @doc """
  Fetches credential schemas from npm/jsDelivr and writes them to the
  configured schemas directory.

  Wipes and recreates the directory to ensure a clean install, then
  downloads all matching schemas.

  Returns `{:ok, count}` on success or `{:error, reason}` on failure.
  """
  @spec refresh(excluded :: [String.t()]) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def refresh(excluded \\ @default_excluded_adaptors) do
    {:ok, schemas_path} = Application.fetch_env(:lightning, :schemas_path)

    excluded_full = Enum.map(excluded, &"@openfn/#{&1}")

    case fetch_package_list() do
      {:ok, packages} ->
        tmp_dir =
          Path.join(schemas_path, ".tmp_#{System.unique_integer([:positive])}")

        File.mkdir_p!(tmp_dir)

        results =
          packages
          |> Enum.filter(&Regex.match?(~r/@openfn\/language-\w+/, &1))
          |> Enum.reject(&(&1 in excluded_full))
          |> Task.async_stream(
            &persist_schema(tmp_dir, &1),
            ordered: false,
            max_concurrency: 5,
            timeout: 30_000
          )
          |> Enum.to_list()

        count =
          Enum.count(results, fn
            {:ok, :ok} -> true
            _ -> false
          end)

        # Only replace the existing schemas if we got at least one
        if count > 0 do
          schemas_path
          |> File.ls!()
          |> Enum.reject(&String.starts_with?(&1, ".tmp_"))
          |> Enum.each(&File.rm!(Path.join(schemas_path, &1)))

          tmp_dir
          |> File.ls!()
          |> Enum.each(fn file ->
            File.rename!(Path.join(tmp_dir, file), Path.join(schemas_path, file))
          end)
        end

        File.rm_rf(tmp_dir)

        {:ok, count}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Failed to refresh credential schemas: #{inspect(error)}")

      {:error, error}
  end

  @doc """
  Parses CLI args to build the excluded adaptors list.

  If `args` starts with `["--exclude" | names]`, those names are merged
  with the default exclusions. Otherwise the defaults are returned.
  """
  @spec parse_excluded([String.t()]) :: [String.t()]
  def parse_excluded(args) do
    case args do
      ["--exclude" | adaptor_names] when adaptor_names != [] ->
        (adaptor_names ++ @default_excluded_adaptors) |> Enum.uniq()

      _ ->
        @default_excluded_adaptors
    end
  end

  defp fetch_package_list do
    case HTTPoison.get(
           "https://registry.npmjs.org/-/user/openfn/package",
           [],
           hackney: [pool: :default],
           recv_timeout: 15_000
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        packages = body |> Jason.decode!() |> Map.keys()
        {:ok, packages}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, "NPM returned #{status}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp persist_schema(dir, package_name) do
    url =
      "https://cdn.jsdelivr.net/npm/#{package_name}/configuration-schema.json"

    case HTTPoison.get(url, [],
           hackney: [pool: :default],
           recv_timeout: 15_000
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        write_schema(dir, package_name, body)
        :ok

      {:ok, %HTTPoison.Response{status_code: _status}} ->
        :skipped

      {:error, _reason} ->
        :error
    end
  end

  defp write_schema(dir, package_name, data) do
    filename =
      String.replace(package_name, "@openfn/language-", "") <> ".json"

    path = Path.join(dir, filename)
    File.write!(path, data)
  end
end
