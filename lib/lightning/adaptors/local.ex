defmodule Lightning.Adaptors.Local do
  @moduledoc """
  Filesystem implementation of `Lightning.Adaptors.Strategy`.

  Serves adaptor metadata, schemas, and icons from an on-disk OpenFn
  adaptors monorepo checkout. Gated by `LOCAL_ADAPTORS=true` and
  `OPENFN_ADAPTORS_REPO=/path/to/adaptors` at the runtime-config layer;
  this module only reads the resolved path via
  `Lightning.Adaptors.Config.strategy_opts(__MODULE__)[:path]`.

  Each callback walks the filesystem afresh — caching is the Store's
  responsibility. The module is stateless; no GenServer, no ETS.

  ## Layout

  Walks `$path/packages/*/`, reads each subdirectory's `package.json`
  for the authoritative `name` and `version`. Directories with missing
  or unparseable `package.json` are skipped with `Logger.warning` so a
  malformed entry never crashes boot. Multiple directories sharing the
  same `name` are collapsed into one record: `latest_version` is the
  highest semver and `versions` lists every on-disk path.

  `source: :local` is **not** set here — the Store stamps it before
  upsert. No network calls anywhere in this module.
  """

  @behaviour Lightning.Adaptors.Strategy

  alias Lightning.Adaptors.Config

  require Logger

  @schema_filename "configuration-schema.json"
  @icon_exts ~w(png svg)

  @impl Lightning.Adaptors.Strategy
  def list_adaptors do
    with {:ok, records} <- discover() do
      {:ok,
       Enum.map(records, fn %{name: name, latest_version: v} ->
         %{name: name, latest_version: v}
       end)}
    end
  end

  @impl Lightning.Adaptors.Strategy
  def fetch_adaptor(name) when is_binary(name) do
    with {:ok, records} <- discover() do
      case Enum.find(records, &(&1.name == name)) do
        nil -> {:error, :not_found}
        record -> {:ok, build_adaptor_record(record)}
      end
    end
  end

  @impl Lightning.Adaptors.Strategy
  def fetch_icon(name, shape)
      when is_binary(name) and shape in [:square, :rectangle] do
    with {:ok, records} <- discover() do
      case Enum.find(records, &(&1.name == name)) do
        nil -> {:error, :not_found}
        %{latest_path: path} -> read_icon(path, shape)
      end
    end
  end

  @impl Lightning.Adaptors.Strategy
  def fetch_icons(_opts \\ []) do
    with {:ok, records} <- discover() do
      icons =
        Enum.reduce(records, %{}, fn record, acc ->
          Enum.reduce([:square, :rectangle], acc, fn shape, inner ->
            case read_icon(record.latest_path, shape) do
              {:ok, %{data: bytes, ext: ext}} ->
                entry = %{
                  data: bytes,
                  ext: ext,
                  sha256: :crypto.hash(:sha256, bytes)
                }

                Map.update(
                  inner,
                  record.name,
                  %{shape => entry},
                  &Map.put(&1, shape, entry)
                )

              {:error, _} ->
                inner
            end
          end)
        end)

      {:ok, icons}
    end
  end

  defp discover do
    case Config.strategy_opts(__MODULE__)[:path] do
      nil ->
        Logger.warning(
          "Lightning.Adaptors.Local: :path is not configured " <>
            "(set OPENFN_ADAPTORS_REPO or :lightning, Lightning.Adaptors.Local, path:)"
        )

        {:error, :no_repo_path}

      path ->
        records =
          path
          |> Path.join("packages")
          |> Path.join("*")
          |> Path.wildcard()
          |> Enum.filter(&File.dir?/1)
          |> Enum.flat_map(&read_package_dir/1)
          |> group_by_name()

        {:ok, records}
    end
  end

  defp read_package_dir(dir) do
    pkg_json_path = Path.join(dir, "package.json")

    with {:ok, body} <- File.read(pkg_json_path),
         {:ok, %{"name" => name, "version" => version} = parsed}
         when is_binary(name) and is_binary(version) <- Jason.decode(body) do
      [%{name: name, version: version, path: dir, package_json: parsed}]
    else
      other ->
        Logger.warning(
          "Lightning.Adaptors.Local: skipping #{inspect(dir)}: " <>
            "missing or unparseable package.json (#{inspect(other)})"
        )

        []
    end
  end

  defp group_by_name(entries) do
    entries
    |> Enum.group_by(& &1.name)
    |> Enum.map(fn {name, versions} ->
      sorted = Enum.sort_by(versions, & &1.version, &version_descending/2)
      latest = List.first(sorted)

      %{
        name: name,
        latest_version: latest.version,
        latest_path: latest.path,
        latest_package_json: latest.package_json,
        versions: sorted
      }
    end)
  end

  defp version_descending(a, b) do
    case {Version.parse(a), Version.parse(b)} do
      {{:ok, va}, {:ok, vb}} -> Version.compare(va, vb) != :lt
      _ -> a >= b
    end
  end

  defp build_adaptor_record(record) do
    pkg = record.latest_package_json
    {schema_data, schema_sha256} = read_schema(record.latest_path)

    %{
      name: record.name,
      description: pkg["description"],
      homepage: pkg["homepage"],
      repository: extract_repository(pkg["repository"]),
      license: pkg["license"],
      latest_version: record.latest_version,
      deprecated: false,
      schema_data: schema_data,
      schema_sha256: schema_sha256,
      versions: Enum.map(record.versions, &build_version_record/1)
    }
  end

  defp build_version_record(%{version: v, package_json: pkg}) do
    %{
      version: v,
      integrity: nil,
      tarball_url: nil,
      size_bytes: nil,
      dependencies: Map.get(pkg, "dependencies", %{}),
      peer_dependencies: Map.get(pkg, "peerDependencies", %{}),
      published_at: nil,
      deprecated: false
    }
  end

  defp read_schema(dir) do
    case File.read(Path.join(dir, @schema_filename)) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, data} ->
            sha = :sha256 |> :crypto.hash(body) |> Base.encode16(case: :lower)
            {data, sha}

          {:error, _} ->
            {nil, nil}
        end

      {:error, _} ->
        {nil, nil}
    end
  end

  defp read_icon(dir, shape) do
    Enum.find_value(@icon_exts, {:error, :not_found}, fn ext ->
      case File.read(icon_path(dir, shape, ext)) do
        {:ok, bytes} -> {:ok, %{data: bytes, ext: ext}}
        {:error, _} -> nil
      end
    end)
  end

  defp icon_path(dir, shape, ext),
    do: Path.join([dir, "assets", "#{shape}.#{ext}"])

  defp extract_repository(repo) when is_binary(repo), do: repo
  defp extract_repository(%{"url" => url}) when is_binary(url), do: url
  defp extract_repository(_), do: nil
end
