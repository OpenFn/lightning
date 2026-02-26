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

  Does not wipe the directory -- writes new/updated files and keeps
  existing ones.

  Returns `{:ok, count}` on success or `{:error, reason}` on failure.
  """
  @spec refresh(excluded :: [String.t()]) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def refresh(excluded \\ @default_excluded_adaptors) do
    {:ok, schemas_path} = Application.fetch_env(:lightning, :schemas_path)
    File.mkdir_p!(schemas_path)

    excluded_full = Enum.map(excluded, &"@openfn/#{&1}")

    case fetch_package_list() do
      {:ok, packages} ->
        results =
          packages
          |> Enum.filter(&Regex.match?(~r/@openfn\/language-\w+/, &1))
          |> Enum.reject(&(&1 in excluded_full))
          |> Task.async_stream(
            &persist_schema(schemas_path, &1),
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

        {:ok, count}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Failed to refresh credential schemas: #{inspect(error)}")

      {:error, error}
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
