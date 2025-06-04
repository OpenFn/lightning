defmodule Lightning.Adaptors.NPM do
  @behaviour Lightning.Adaptors.Strategy
  require Logger

  @config_schema [
    user: [
      type: :string,
      required: true,
      doc: "NPM user or organization name"
    ],
    max_concurrency: [
      type: :pos_integer,
      default: 10,
      doc: "Maximum number of concurrent requests when fetching package details"
    ],
    timeout: [
      type: :pos_integer,
      default: 30_000,
      doc: "Timeout in milliseconds for individual package detail requests"
    ],
    filter: [
      type: {:or, [{:fun, 1}, nil]},
      default: nil,
      doc:
        "Function to filter package names. Takes a package name string and returns boolean"
    ]
  ]

  @type config() :: [unquote(NimbleOptions.option_typespec(@config_schema))]

  @moduledoc """
  NPM strategy implementation for adaptor registry.

  Config options:
  #{NimbleOptions.docs(@config_schema)}
  """

  @doc "Supported options:\n#{NimbleOptions.docs(@config_schema)}"
  @impl true
  @spec fetch_packages(config :: config()) :: {:ok, [map()]} | {:error, term()}
  def fetch_packages(config) do
    with {:ok, validated_config} <- validate_config(config) do
      Logger.debug("Fetching NPM packages for: #{validated_config[:user]}")

      user_packages(validated_config)
      |> case do
        {:ok, response} ->
          adaptors =
            response
            |> Map.get(:body)
            |> Enum.map(fn {name, _} -> name end)
            |> Enum.filter(validated_config[:filter] || fn _ -> true end)
            |> Task.async_stream(
              &fetch_package(validated_config, &1),
              ordered: false,
              max_concurrency: validated_config[:max_concurrency],
              timeout: validated_config[:timeout]
            )
            |> Stream.map(fn result ->
              case result do
                {:ok, {:error, error}} -> {:error, error}
                {:ok, detail} -> {:ok, detail}
              end
            end)
            |> Stream.filter(&match?({:ok, _}, &1))
            |> Stream.map(fn {:ok, detail} -> detail end)
            |> Enum.to_list()

          {:ok, adaptors}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @impl true
  @spec validate_config(config :: config()) ::
          {:ok, keyword()} | {:error, term()}
  def validate_config(config) do
    NimbleOptions.validate(config, @config_schema)
  end

  @doc """
  Retrieve all packages for a given user or organization. Return empty list if
  application cannot connect to NPM. (E.g., because it's started offline.)
  """
  @spec user_packages(config :: config()) :: Tesla.Env.result()
  def user_packages(config) do
    Tesla.get(client(), "/-/user/#{config[:user]}/package")
  end

  @doc """
  Retrieve all details for an NPM package
  """
  @spec fetch_package(config :: config(), package_name :: String.t()) ::
          Tesla.Env.result()
  def fetch_package(_config, package_name) do
    Logger.debug("Fetching NPM package: #{package_name}")

    Tesla.get(client(), "/#{package_name}")
    |> case do
      {:ok, %Tesla.Env{status: 200, body: details}} ->
        %Lightning.Adaptors.Package{
          name: details["name"],
          repo: details["repository"]["url"],
          latest: details["dist-tags"]["latest"],
          versions:
            Enum.reject(details["versions"], fn {_version, detail} ->
              detail["deprecated"]
            end)
            |> Enum.map(fn {version, _detail} ->
              %{version: version}
            end)
        }

      {:ok, %Tesla.Env{status: 404}} ->
        {:error, :not_found}

      {:error, _} = error ->
        error
    end
  end

  defp client do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, "https://registry.npmjs.org"},
      Tesla.Middleware.JSON
    ])
  end

  @impl true
  def fetch_credential_schema(_adaptor_name, _version) do
    {:error, :not_implemented}
  end

  @impl true
  def fetch_icon(_adaptor_name, _version) do
    {:error, :not_implemented}
  end
end
