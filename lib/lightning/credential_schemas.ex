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

  @doc """
  Fetches credential schemas from npm/jsDelivr and stores them in the
  database via `Lightning.AdaptorData`.

  Used by the `AdaptorRefreshWorker` and the Maintenance LiveView for
  DB-backed storage.

  Returns `{:ok, count}` on success or `{:error, reason}` on failure.
  """
  @spec fetch_and_store(excluded :: [String.t()]) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def fetch_and_store(excluded \\ @default_excluded_adaptors) do
    excluded_full = Enum.map(excluded, &"@openfn/#{&1}")

    case fetch_package_list() do
      {:ok, packages} ->
        results =
          packages
          |> Enum.filter(&Regex.match?(~r/@openfn\/language-\w+/, &1))
          |> Enum.reject(&(&1 in excluded_full))
          |> Task.async_stream(
            &fetch_schema/1,
            ordered: false,
            max_concurrency: 5,
            timeout: 30_000
          )
          |> Enum.to_list()

        entries =
          results
          |> Enum.flat_map(fn
            {:ok, {:ok, name, data}} ->
              [%{key: name, data: data, content_type: "application/json"}]

            _ ->
              []
          end)

        if entries != [] do
          Lightning.AdaptorData.put_many("schema", entries)
        end

        {:ok, length(entries)}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      Logger.error(
        "Failed to fetch and store credential schemas: #{inspect(error)}"
      )

      {:error, error}
  end

  defp schema_client do
    Tesla.client([
      Tesla.Middleware.FollowRedirects,
      {Tesla.Middleware.Timeout, timeout: 15_000}
    ])
  end

  defp npm_client do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, "https://registry.npmjs.org"},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Timeout, timeout: 15_000}
    ])
  end

  defp fetch_schema(package_name) do
    case read_schema_body(package_name) do
      {:ok, body} ->
        name = short_name(package_name)
        {:ok, name, body}

      :skipped ->
        :skipped

      :error ->
        :error
    end
  end

  defp fetch_package_list do
    case local_package_list() do
      {:ok, packages} ->
        {:ok, packages}

      :not_found ->
        http_package_list()
    end
  end

  defp persist_schema(dir, package_name) do
    case read_schema_body(package_name) do
      {:ok, body} ->
        write_schema(dir, package_name, body)
        :ok

      :skipped ->
        :skipped

      :error ->
        :error
    end
  end

  # ---------------------------------------------------------------------------
  # Source-of-truth helpers: try local adaptors repo first, then jsDelivr.
  # ---------------------------------------------------------------------------

  defp read_schema_body(package_name) do
    case local_schema(package_name) do
      {:ok, body} ->
        {:ok, body}

      :not_found ->
        http_schema(package_name)
    end
  end

  defp local_schema(package_name) do
    case Lightning.AdaptorRegistry.local_repo_path() do
      repo when is_binary(repo) ->
        path =
          Path.join([
            repo,
            "packages",
            short_name(package_name),
            "configuration-schema.json"
          ])

        case File.read(path) do
          {:ok, body} ->
            Logger.debug("Loaded schema #{package_name} from local repo")
            {:ok, body}

          {:error, _reason} ->
            :not_found
        end

      _ ->
        :not_found
    end
  end

  defp http_schema(package_name) do
    url =
      "https://cdn.jsdelivr.net/npm/#{package_name}/configuration-schema.json"

    case Tesla.get(schema_client(), url) do
      {:ok, %Tesla.Env{status: 200, body: body}} -> {:ok, body}
      {:ok, %Tesla.Env{}} -> :skipped
      {:error, _reason} -> :error
    end
  end

  defp local_package_list do
    case Lightning.AdaptorRegistry.local_repo_path() do
      repo when is_binary(repo) ->
        packages_dir = Path.join(repo, "packages")

        case File.ls(packages_dir) do
          {:ok, dirs} ->
            packages = Enum.map(dirs, &("@openfn/language-" <> &1))
            Logger.debug("Using #{length(packages)} packages from local repo")
            {:ok, packages}

          {:error, _reason} ->
            :not_found
        end

      _ ->
        :not_found
    end
  end

  defp http_package_list do
    case Tesla.get(npm_client(), "/-/user/openfn/package") do
      {:ok, %Tesla.Env{status: 200, body: body}} when is_map(body) ->
        {:ok, Map.keys(body)}

      {:ok, %Tesla.Env{status: 200, body: body}} when is_binary(body) ->
        {:ok, body |> Jason.decode!() |> Map.keys()}

      {:ok, %Tesla.Env{status: status}} ->
        {:error, "NPM returned #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp short_name(package_name),
    do: String.replace(package_name, "@openfn/language-", "")

  defp write_schema(dir, package_name, data) do
    path = Path.join(dir, short_name(package_name) <> ".json")
    File.write!(path, data)
  end
end
