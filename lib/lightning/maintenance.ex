defmodule Lightning.Maintenance do
  @moduledoc """
  Maintenance operations for the Lightning platform.

  Provides functions to install adaptor icons and credential schemas.
  These are called by both mix tasks and the admin LiveView, so they
  must work without Mix being available (e.g. in production releases).
  """

  require Logger

  @adaptors_tar_url "https://github.com/OpenFn/adaptors/archive/refs/heads/main.tar.gz"

  @default_excluded_adaptors [
    "@openfn/language-common",
    "@openfn/language-devtools",
    "@openfn/language-divoc"
  ]

  # ---------------------------------------------------------------------------
  # Adaptor Icons
  # ---------------------------------------------------------------------------

  @doc """
  Downloads and installs adaptor icons from the OpenFn adaptors repository.

  Fetches a tar.gz archive, extracts it, copies PNG icons to the configured
  `adaptor_icons_path`, and writes a JSON manifest file.

  Returns `{:ok, message}` on success or `{:error, reason}` on failure.
  """
  @spec install_adaptor_icons() :: {:ok, String.t()} | {:error, String.t()}
  def install_adaptor_icons do
    target_dir = Application.get_env(:lightning, :adaptor_icons_path)

    try do
      case File.mkdir_p(target_dir) do
        :ok ->
          :ok

        {:error, reason} ->
          raise "Couldn't create the adaptors images directory: #{target_dir}, got :#{reason}."
      end

      working_dir = tmp_dir!()
      tar = fetch_body!(@adaptors_tar_url)
      :ok = extract_tar!(tar, working_dir)

      adaptor_icons = save_icons(working_dir, target_dir)
      manifest_path = Path.join(target_dir, "adaptor_icons.json")
      File.write!(manifest_path, Jason.encode!(adaptor_icons))

      {:ok,
       "Adaptor icons installed successfully. #{map_size(adaptor_icons)} adaptors updated."}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp adapter, do: Application.get_env(:tesla, __MODULE__, [])[:adapter]

  defp fetch_body!(url) do
    client = Tesla.client([Tesla.Middleware.FollowRedirects], adapter())
    Tesla.get!(client, url).body
  end

  defp tmp_dir! do
    dir =
      Path.join([
        System.tmp_dir!(),
        "lightning-adaptor",
        "#{System.unique_integer([:positive])}"
      ])

    {:ok, _} = File.rm_rf(dir)
    :ok = File.mkdir_p(dir)
    dir
  end

  defp extract_tar!(tar, working_dir) do
    case :erl_tar.extract({:binary, tar}, [
           :compressed,
           cwd: to_charlist(working_dir)
         ]) do
      :ok -> :ok
      other -> raise "Couldn't unpack archive: #{inspect(other)}"
    end
  end

  defp save_icons(working_dir, target_dir) do
    [working_dir, "**", "packages", "*", "assets", "{rectangle,square}.png"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.map(fn icon_path ->
      [icon_name, "assets", adapter_name | _rest] =
        icon_path |> Path.split() |> Enum.reverse()

      dest_name = adapter_name <> "-" <> icon_name
      File.cp!(icon_path, Path.join(target_dir, dest_name))

      %{
        adaptor: adapter_name,
        shape: Path.rootname(icon_name),
        src: "/images/adaptors/#{dest_name}"
      }
    end)
    |> Enum.group_by(& &1.adaptor)
    |> Map.new(fn {adaptor, srcs} ->
      {adaptor, Map.new(srcs, &{&1.shape, &1.src})}
    end)
  end

  # ---------------------------------------------------------------------------
  # Credential Schemas
  # ---------------------------------------------------------------------------

  @doc """
  Downloads and installs JSON credential schemas for OpenFn language packages.

  Queries the NPM registry for all `@openfn/language-*` packages, then
  fetches each configuration schema from jsDelivr and saves them to the
  configured `schemas_path`. Runs up to 5 concurrent downloads.

  `extra_excluded` is an optional list of bare adaptor names (e.g.
  `["language-foo"]`) to exclude in addition to the defaults.

  Returns `{:ok, message}` on success or `{:error, reason}` on failure.
  """
  @spec install_schemas(list(String.t())) ::
          {:ok, String.t()} | {:error, String.t()}
  def install_schemas(extra_excluded \\ []) do
    dir = Application.get_env(:lightning, :schemas_path)

    excluded =
      @default_excluded_adaptors ++
        Enum.map(extra_excluded, &"@openfn/#{&1}")

    try do
      :ok = init_schema_dir!(dir)

      packages = fetch_openfn_packages!()

      result =
        packages
        |> Enum.reject(&(&1 in excluded))
        |> Task.async_stream(&persist_schema!(dir, &1),
          ordered: false,
          max_concurrency: 5,
          timeout: 30_000
        )
        |> Enum.to_list()

      {:ok, "Schemas installation has finished. #{length(result)} installed."}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp init_schema_dir!(nil), do: raise("Schema directory not provided.")

  defp init_schema_dir!(dir) do
    File.rm_rf(dir)

    case File.mkdir_p(dir) do
      :ok ->
        :ok

      {:error, reason} ->
        raise "Couldn't create the schemas directory: #{dir}, got :#{reason}."
    end
  end

  defp fetch_openfn_packages! do
    client =
      Tesla.client(
        [
          {Tesla.Middleware.BaseUrl, "https://registry.npmjs.org"},
          Tesla.Middleware.JSON,
          {Tesla.Middleware.Timeout, timeout: 15_000}
        ],
        adapter()
      )

    case Tesla.get(client, "/-/user/openfn/package") do
      {:ok, %Tesla.Env{status: 200, body: body}} when is_map(body) ->
        body
        |> Map.keys()
        |> Enum.filter(&Regex.match?(~r/@openfn\/language-\w+/, &1))

      {:ok, %Tesla.Env{status: 200, body: body}} when is_binary(body) ->
        body
        |> Jason.decode!()
        |> Map.keys()
        |> Enum.filter(&Regex.match?(~r/@openfn\/language-\w+/, &1))

      {:ok, %Tesla.Env{status: status_code}} ->
        raise "Unable to access openfn user packages. status=#{status_code}"

      {:error, _} ->
        raise "Unable to connect to NPM; no adaptors fetched."
    end
  end

  defp persist_schema!(dir, package_name) do
    url =
      "https://cdn.jsdelivr.net/npm/#{package_name}/configuration-schema.json"

    client =
      Tesla.client(
        [
          Tesla.Middleware.FollowRedirects,
          {Tesla.Middleware.Timeout, timeout: 15_000}
        ],
        adapter()
      )

    case Tesla.get(client, url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        path =
          Path.join(
            dir,
            String.replace(package_name, "@openfn/language-", "") <> ".json"
          )

        File.write!(path, body)

      {:ok, %Tesla.Env{status: status_code}} ->
        Logger.warning(
          "Unable to fetch #{package_name} configuration schema. status=#{status_code}"
        )

      {:error, _} ->
        raise "Unable to access #{package_name}"
    end
  end
end
