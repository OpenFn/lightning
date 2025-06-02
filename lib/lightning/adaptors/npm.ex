defmodule Lightning.Adaptors.NPM do
  @moduledoc """
  NPM strategy implementation for adaptor registry.
  """
  @behaviour Lightning.Adaptors.Strategy
  require Logger

  @type config :: [
          user: String.t(),
          max_concurrency: pos_integer(),
          timeout: pos_integer(),
          filter: (String.t() -> boolean())
        ]

  @impl true
  @spec fetch_adaptors(config :: config()) :: {:ok, [map()]} | {:error, term()}
  def fetch_adaptors(config) do
    with {:ok, validated_config} <- validate_config(config) do
      user_packages(validated_config[:user])
      |> case do
        {:ok, response} ->
          response
          |> Map.get(:body)
          |> Enum.map(fn {name, _} -> name end)
          |> Enum.filter(validated_config[:filter])
          |> Task.async_stream(
            &fetch_package_details/1,
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

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp validate_config(config) do
    config_schema =
      NimbleOptions.new!(
        user: [
          type: :string,
          required: true,
          doc: "NPM user or organization name"
        ],
        max_concurrency: [
          type: :pos_integer,
          default: 10,
          doc:
            "Maximum number of concurrent requests when fetching package details"
        ],
        timeout: [
          type: :pos_integer,
          default: 30_000,
          doc: "Timeout in milliseconds for individual package detail requests"
        ],
        filter: [
          type: {:fun, 1},
          default: fn _ -> true end,
          doc:
            "Function to filter package names. Takes a package name string and returns boolean"
        ]
      )

    NimbleOptions.validate(config, config_schema)
  end

  @doc """
  Retrieve all packages for a given user or organization. Return empty list if
  application cannot connect to NPM. (E.g., because it's started offline.)
  """
  @spec user_packages(user :: String.t()) :: Tesla.Env.result()
  def user_packages(user) do
    Tesla.get(client(), "/-/user/#{user}/package")
  end

  @doc """
  Retrieve all details for an NPM package
  """
  @spec package_detail(package_name :: String.t()) :: Tesla.Env.result()
  def package_detail(package_name) do
    Tesla.get(client(), "/#{package_name}")
  end

  defp fetch_package_details(package_name) do
    package_detail(package_name)
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
